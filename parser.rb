require 'nokogiri'
require 'breasal'
require 'date'
require 'uri'
require 'pp'

def clean_end(s)
  # Removes trailing spaces including Unicode whitespace (eg char 160) from the end of a string
  # Returns nil if the resulting string is empty
  s.strip!
  s.sub!(/\p{Zs}+$/, '')
  return nil if s == ''
  s
end

def cleanup(items)
  # Regex doesn't work across multiple text lines by default
  items.map { |i| i.inner_html.strip.gsub(/&.+;/, '').gsub(/<span>.*<\/span>/m, '').gsub(/[\t\r\n]/m, '') }
end

def parse_details(html)
  doc = Nokogiri::HTML(html)
  app = {}
  lists = doc.search("ul.list")

  # First ul is Application Progress Summary
  items = lists[0].search("li div")
  values = cleanup(items)

  app['date_received'] = Date.parse(values[0]) if values[0].match(DATE_REGEX)
  app['status'] = clean_end(values[1])
  app['on_notice_to'] = Date.parse(values[2]) if values[2].match(DATE_REGEX)
  app['recommendation'] = clean_end(values[3])
  app['date_committee'] = Date.parse(values[4]) if values[4].match(DATE_REGEX)
  app['decision'] = clean_end(values[5])
  app['date_appeal_lodged'] = Date.parse(values[6]) if values[6].match(DATE_REGEX) # FIXME Is this actually a date or a Yes/No?
  app['appeal_decision'] = clean_end(values[7])

  # Second ul is Application Details

  items = lists[1].search("li div")
  # Regex doesn't work across multiple text lines by default
  values = items.map { |i| i.inner_html.strip.gsub(/&.+;/m, '') }

  app['council_reference'] = clean_end(items[0].children[2].inner_text)
  app['application_type'] = clean_end(items[2].children[2].inner_text)
  app['applicant_name'] = clean_end(items[5].children[2].inner_text)
  app['agent_name'] = clean_end(items[6].children[2].inner_text)
  app['wards'] = clean_end(items[7].children[2].inner_text)

  en_string = values[8].match(/Easting.+?(\d+).+?Northing.+?(\d+)/)
  app['easting'] = en_string[1].to_i
  app['northing'] = en_string[2].to_i
  en = Breasal::EastingNorthing.new(easting: app['easting'], northing: app['northing'], type: :gb)
  app['latitude'] = en.to_wgs84[:latitude]
  app['longitude'] = en.to_wgs84[:longitude]

  app['appeal_submitted'] = clean_end(items[9].children[2].inner_text)
  app['appeal_decision'] = clean_end(items[10].children[2].inner_text)

  if items[11].children[2].inner_text.match(/\d+/)
    app['case_officer_phone'] = clean_end(items[11].children[2].inner_text.gsub(/[\r\n\t]/, '')).match(/(\d+)/)[1].sub(/^44/, '0')
  end
  
  app['division'] = clean_end(items[12].children[2].inner_text.gsub('-', ''))
  app['case_officer_name'] = clean_end(items[13].children[2].inner_text)
  app['determination_level'] = clean_end(items[14].children[2].inner_text)
  app['existing_land_use'] = clean_end(items[15].children[2].inner_text)
  app['proposed_land_use'] = clean_end(items[16].children[2].inner_text)


  # Third ul is Other Information Available for Planning Application...

  links = doc.search("a.FooterLinks")
  app['documents_url'] = SITE_URL + links[0]['href'].gsub(/[\r\n\t]/, '')
  app['dates_url'] = URI::encode(BASE_URL + links[1]['href']).gsub(/%0./m, '')
  app['checks_url'] = URI::encode(BASE_URL + links[2]['href']).gsub(/%0./m, '')
  app['meetings_url'] = URI::encode(BASE_URL + links[3]['href']).gsub(/%0./m, '')
  app['constraints_url'] = URI::encode(BASE_URL + links[4]['href']).gsub(/%0./m, '')
  app['site_history_url'] = URI::encode(BASE_URL + links[5]['href']).gsub(/%0./m, '') if links[5]

  app
end

def parse_dates(html)
  doc = Nokogiri::HTML(html)
  app = {}
  dates = []
  doc.search(".dataview ul div").each { |row| dates << row.children[2].inner_text }
  
  app['date_received'] = Date.parse(dates[0]) if dates[0].match(DATE_REGEX)
  app['date_first_advertised'] = Date.parse(dates[1]) if dates[1].match(DATE_REGEX)
  app['date_registered'] = Date.parse(dates[2]) if dates[2].match(DATE_REGEX)
  app['date_first_site_notice'] = Date.parse(dates[3]) if dates[3].match(DATE_REGEX)
  app['date_valid'] = Date.parse(dates[4]) if dates[4].match(DATE_REGEX)
  app['on_notice_to'] = Date.parse(dates[5]) if dates[5].match(DATE_REGEX)
  app['date_validated'] = Date.parse(dates[6]) if dates[6].match(DATE_REGEX)
  app['target_date'] = Date.parse(dates[7]) if dates[7].match(DATE_REGEX)
  app['stat_cons_expiry_date'] = Date.parse(dates[8]) if dates[8].match(DATE_REGEX)
  app['decision_expiry_date'] = Date.parse(dates[9]) if dates[9].match(DATE_REGEX)
  app['first_consultation_date'] = Date.parse(dates[10]) if dates[10].match(DATE_REGEX)
  app['extended_expiry_date'] = Date.parse(dates[11]) if dates[11].match(DATE_REGEX)
  
  app
end

def parse_documents(html)
  doc = Nokogiri::HTML(html)
  docs = []

  doc.search("#tblContent td a").each do |d|
    # title = d.inner_text.strip.match(/^[\d\w]+?_\s*(.+?)\.pdf/)[1].gsub('_', ' ')
    
    docs << {
      'title' => d.inner_text.strip,
      'url' => URI::encode(SITE_URL + d['href']),
      'date_last_seen' => Date.today.to_s
    }
  end

  docs
end
