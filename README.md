# Merton Council planning applications scraper

This scrapes planning applications data from [Merton Council's planning database website](http://planning.merton.gov.uk/Northgate/PlanningExplorerAA/GeneralSearch.aspx) and puts it in an SQLite database.

Merton Council runs [Northgate Planning Explorer](https://www.northgateps.com).

This scraper is designed to run once per 24 hours.

It runs on [Morph](https://morph.io). To get started [see the documentation](https://morph.io/documentation).

## Schema

The schema is based on the core elements from [planningalerts.org.au](https://www.planningalerts.org.au/how_to_write_a_scraper).

## Installation

    $ git clone https://github.com/adrianshort/merton-planning-applications.git
    $ cd merton-planning-applications
    $ bundle

### Configuration

According to the principle of _one codebase, many deploys_, this scraper is [configured using environment variables](https://12factor.net/config) rather than by editing constants in the code.


|Name|Purpose|Default|Required?|
|------------------|-----------------------------------------|----------|
|MORPH_DELAY     |Minimum delay in seconds between HTTP requests to the server.|10|No|
|MORPH_USER_AGENT|User agent string sent as an HTTP request header.|_None_|Yes|
|MORPH_LOG_LEVEL |Controls the level of detail in the output logs according to [Ruby's `Logger` class](https://ruby-doc.org/stdlib-2.1.0/libdoc/logger/rdoc/Logger.html) constants.|1 _(Logger::INFO)_|No|

## Running

    $ bundle exec ruby scraper.rb

## Logging

[Log messages are written unbuffered to `STDOUT`.](https://12factor.net/logs) You can redirect them to a file or the log drain of your choice.

    $ bundle exec ruby scraper.rb >> log.txt

Morph.io will only show the first 10,000 lines of log output. This constraint doesn't apply when running elsewhere, eg on your local machine.

## Similar projects

- [maxharlow/scrape-planning-northgate](https://github.com/maxharlow/scrape-planning-northgate) (Node)
- [adrianshort/planningalerts](https://github.com/adrianshort/planningalerts), especially the [Python scrapers for Northgate Planning Explorer](https://github.com/adrianshort/planningalerts/blob/master/python_scrapers/PlanningExplorer.py) - not by me, just a copy of this project's codebase

## Tags

- Merton
- Merton Council
- London
- UK
- localgov
- localgovdigital
- opendata
- Morph
- ScraperWiki
- planning
- Planning Alerts
- plantech
- civictech

## Author

By [Adrian Short](https://www.adrianshort.org/).

This project is not by or affiliated with Merton Council.
