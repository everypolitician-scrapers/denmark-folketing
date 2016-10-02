#!/bin/env ruby
# encoding: utf-8

require 'cgi'
require 'field_serializer'
require 'nokogiri'
require 'open-uri'
require 'pry'
require 'scraperwiki'

# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '.cache'
require 'scraped_page_archive/open-uri'

class Page
  include FieldSerializer

  def initialize(url)
    @url = url
  end

  def noko
    @noko ||= Nokogiri::HTML(open(url).read)
  end

  private

  attr_reader :url
end

class PartiesPage < Page
  field :parties do
    noko.css('.telbogTable tr a[href*="party="]').map do |a|
      {
        name: a.text,
        url:  URI.join(url, a.attr('href')).to_s,
      }
    end
  end
end

def noko_for(url)
  Nokogiri::HTML(open(url).read) 
end

def scrape_party_list(url)
  PartiesPage.new(url).to_h[:parties].each do |party|
    scrape_party party[:url]
  end
end

def scrape_party(url)
  noko = noko_for(url)
  noko.css('.telbogTable').xpath('.//tr[td]').each do |tr|
    tds = tr.css('td')
    mplink = tr.at_css('a[href*="/Members/"]/@href').text
    mp_url = URI.join(url, URI.escape(mplink))
    mp_noko = noko_for(mp_url)
    box = mp_noko.css('#mainform')
    memberships = box.xpath('.//strong[contains(.,"Member period")]/following-sibling::text()').map(&:text)

    data = { 
      id: mp_url.to_s[%r(/Members/(.*).aspx), 1],
      name: box.css('h1').text.strip,
      given_name: tds[0].text.strip,
      family_name: tds[1].text.strip,
      party: tds[2].text.strip,
      party_id: CGI.parse(URI.parse(url).query)['party'].first.gsub(/[{}]/,''),
      constituency: memberships.first[/ in (.*?) from/, 1].sub('greater constituency','').strip,
      email: box.css('div.person a[href*="mailto:"]/@href').text.gsub('mailto:','').tr('|/',';'),
      homepage: box.css('div.person a[href*="http"]/@href').text,
      image: box.css('div.person img/@src').text,
      memberships: memberships.join("+++"),
      term: '2015',
      source: mp_url.to_s,
    }
    data[:image] = URI.join(mp_url, URI.escape(data[:image])).to_s unless data[:image].to_s.empty?
    ScraperWiki.save_sqlite([:id, :term], data)
  end
end

term = {
  id: '2015',
  name: '2015–',
  start_date: '2015',
}
ScraperWiki.save_sqlite([:id], term, 'terms')

scrape_party_list('http://www.thedanishparliament.dk/Members/Members_in_party_groups.aspx')
