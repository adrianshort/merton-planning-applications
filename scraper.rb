require 'http'
require 'nokogiri'
require 'uri'
require 'scraperwiki'
require 'pp'
require_relative './parser'
require 'date'
require 'logger'
require 'securerandom'

# Northgate Planning Explorer

SITE_URL = 'https://planning.merton.gov.uk'
BASE_URL = SITE_URL + '/Northgate/PlanningExplorerAA/Generic/'

def crawl_delay
  sleep DELAY_S
end

DELAY_S = ENV['MORPH_DELAY'].to_f || 10 # seconds. Conservatively slow by default. Scrapes approx 360 pages per hour.
USER_AGENT = ENV['MORPH_USER_AGENT']
DATE_REGEX = /\d{2}-\d{2}-\d{4}/

$stdout.sync = true # Flush output buffer after every write so log messages appear immediately.
logger = Logger.new($stdout)
logger.level = ENV['MORPH_LOG_LEVEL'].to_i || Logger::INFO
logger.info "Scraper starts. Let's do this."
logger.info "Delay between requests is #{DELAY_S} seconds."
logger.info "User agent is: #{USER_AGENT}"
logger.info "Log level is: #{logger.level}"

# General search
URL = SITE_URL + '/Northgate/PlanningExplorerAA/GeneralSearch.aspx'

form_vars = {
  'cboSelectDateValue' => 'DATE_RECEIVED',
  'csbtnSearch' => 'Search' # required
}

# If both MORPH_DAYS and MORPH_MONTHS are set, MORPH_DAYS should be used.

unless ENV['MORPH_DAYS'] || ENV['MORPH_MONTHS']
  logger.fatal "Neither MORPH_MONTHS nor MORPH_DAYS set. Nothing to scrape. Exiting."
  exit 1
end

if ENV['MORPH_MONTHS']
  form_vars.merge!({
    'cboMonths' => ENV['MORPH_MONTHS'],
    'rbGroup' => 'rbMonth'
  })
end

if ENV['MORPH_DAYS']
  form_vars.merge!({
    'cboMonths' => nil,
    'cboDays' => ENV['MORPH_DAYS'],
    'rbGroup' => 'rbDay'
  })
end

form_vars.merge!({ 'cboStatusCode' => ENV['MORPH_STATUS']}) if ENV['MORPH_STATUS']

logger.info "Form variables: #{form_vars.to_s}"

headers = {
  'Origin' => SITE_URL,
  'Referer' => URL,
  'User-Agent' => USER_AGENT
}

logger.debug "HTTP request headers:"
logger.debug(headers.to_s)

logger.debug "GET: " + URL
response = HTTP.headers(headers).get(URL)
logger.debug "Response code: HTTP " + response.code.to_s

if response.code == 200
  doc = Nokogiri::HTML(response.to_s)
  asp_vars = {
    '__VIEWSTATE' => doc.at('#__VIEWSTATE')['value'],
    '__VIEWSTATEGENERATOR' => doc.at('#__VIEWSTATEGENERATOR')['value'],
    '__EVENTVALIDATION' => doc.at('#__EVENTVALIDATION')['value']
   }
else
  logger.fatal "Bad response from search page. Response code: #{response.code.to_s}. Exiting."
  exit 1
end

cookies = {}
response.cookies.each { |c| cookies[c.name] = c.value }

form_vars.merge!(asp_vars)

logger.debug "GET: " + URL
response2 = HTTP.headers(headers).cookies(cookies).post(URL, :form => form_vars)
logger.debug "Response code: HTTP " + response2.code.to_s

if response2.code == 302
  # Follow the redirect manually
  # Set the page size (PS) to max so we don't have to page through search results
  results_url = URI::encode(SITE_URL + response2.headers['Location'].gsub!('PS=10', 'PS=99999'))
  
  logger.debug "GET: " + URL
  response3 = HTTP.headers(headers).cookies(cookies).get(results_url)
  logger.debug "Response code: HTTP " + response3.code.to_s
  doc = Nokogiri::HTML(response3.to_s)
else
  logger.fatal "Didn't get redirected from search. Exiting."
  exit 1
end

rows = doc.search("table.display_table tr")
logger.info "Found #{rows.size - 1} applications in search results."

app_defaults = {
  'la_name' => 'Merton Borough Council',
  'la_slug' => 'merton',
  'la_gss' => 'E09000024', # https://mapit.mysociety.org/area/2500.html
  'date_details_scraped' => nil,
  'date_documents_scraped' => nil,
  'date_dates_scraped' => nil
}
logger.debug "Application defaults: "
logger.debug app_defaults.to_s

# Iterate over search results
rows.each do |row|
  if row.at("td") # skip header row which only has th's
    cells = row.search("td")
    ref = cells[0].inner_text.strip

    app = app_defaults.merge(
      'created_at' => Time.now.to_s,
      'uuid' => SecureRandom.uuid
    )

    begin
      res = ScraperWiki.select("* from applications where council_reference=?", ref)
    rescue # In case the table doesn't exist, which it won't on first run
      true
    end
    
    app = res[0] if res && res[0] # res will be nil if the table doesn't exist; [] if that record doesn't exist

    app['council_reference'] = ref
    app['info_url'] = URI::encode(BASE_URL + cells[0].at("a")['href'].strip)
    app['info_url'].gsub!(/%0./, '') # FIXME. Strip junk chars from URL - how can we prevent this?


    app['address'] = cells[1].inner_text.strip
    app['description'] = cells[2].inner_text.strip
    app['status'] = cells[3].inner_text.strip
    
    raw_date_received = cells[4].inner_text.strip
    
    if raw_date_received != '--'
      app['date_received'] = Date.parse(raw_date_received)
    else
      app['date_received'] = nil
    end
    
    app['decision'] = cells[5].inner_text.strip
    app['date_scraped'] = Date.today.to_s

    app['updated_at'] = Time.now.to_s
    ScraperWiki.save_sqlite(['council_reference'], app, 'applications')
  end
end

# Scrape details for all apps that don't have them
apps = ScraperWiki.select("* from applications where date_details_scraped is null or date_details_scraped < ? order by date_received desc", Date.today.to_s)

logger.info "Scraping details for #{apps.size} applications."

i = 0
apps.each do |app|
  i += 1
  logger.info "#{i} of #{apps.size}: Scraping details for app: #{app['council_reference']}."
  crawl_delay
  
  # Scrape details page
  res = HTTP.headers(headers).cookies(cookies).get(app['info_url'])
  if res.code == 200
    # Parse details page
    parsed_details = parse_details(res.to_s)
    app.merge!(parsed_details)
    app['date_details_scraped'] = Date.today.to_s
    app['updated_at'] = Time.now.to_s
    ScraperWiki.save_sqlite(['council_reference'], app, 'applications')
  else
    logger.error "Failed to get #{app['info_url']} - HTTP " + res.code.to_s # FIXME improve message
  end
end

# Scrape dates page for apps that don't have them
apps = ScraperWiki.select("* from applications where date_dates_scraped is null or date_dates_scraped < ? order by date_received desc", Date.today.to_s)
logger.info "Scraping dates for #{apps.size} applications."

i = 0
apps.each do |app|
  i += 1
  logger.info "#{i} of #{apps.size}: Scraping dates for #{app['council_reference']}."
  crawl_delay
  
  # Scrape dates page
  res = HTTP.headers(headers).cookies(cookies).get(app['dates_url'])

  if res.code == 200
    # Parse dates page
    parsed_dates = parse_dates(res.to_s)
    app.merge!(parsed_dates)
    app['date_dates_scraped'] = Date.today.to_s
    app['updated_at'] = Time.now.to_s
    ScraperWiki.save_sqlite(['council_reference'], app, 'applications')
  else
    logger.error "Error: " + res.code.to_s # FIXME improve message
  end
end

# Scrape documents for apps that don't have them
apps = ScraperWiki.select("* from applications where date_documents_scraped is null or date_documents_scraped < ? order by date_received desc", Date.today.to_s)
logger.info "Scraping documents for #{apps.size} applications."

i = 0
apps.each do |app|
  i += 1
  logger.info "#{i} of #{apps.size}: Scraping documents for #{app['council_reference']}."
  crawl_delay
  
  # Scrape documents page
  res = HTTP.headers(headers).cookies(cookies).get(app['documents_url'])

  if res.code == 200
    # Parse documents page
    docs = parse_documents(res.to_s)

    docs.each do |d|
      d['council_reference'] = app['council_reference']
      ScraperWiki.save_sqlite(['council_reference', 'url'], d, 'documents')
    end

    app['documents_qty'] = docs.size
    app['date_documents_scraped'] = Date.today.to_s
    ScraperWiki.save_sqlite(['council_reference'], app, 'applications')
  else
    logger.error "Error: " + res.code.to_s # FIXME improve message
  end
end

logger.info "Scraper finishes. We did it."
logger.close
