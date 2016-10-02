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
        url:  full_url(a.attr('href')).to_s,
      }
    end
  end

  private

  # We want to add a default '?pagesize=100' to all links
  def full_url(rel)
    uri = URI.join(url, rel)
    new_args = URI.decode_www_form(uri.query || '') << ["pagesize", "100"]
    uri.query = URI.encode_www_form(new_args)
    uri
  end
end

class PartyPage < Page
  field :members do
    noko.css('.telbogTable').xpath('.//tr[td]').map do |tr|
      PartyPageMember.new(tr, url).to_h
    end
  end
end

class PartyPageMember
  include FieldSerializer

  def initialize(row, url)
    @row = row
    @url = url
  end

  field :id do
    member_url.to_s[%r(/Members/(.*).aspx), 1]
  end

  field :given_name do
    tds[0].text.strip
  end

  field :family_name do
    tds[1].text.strip
  end

  field :party do
    tds[2].text.strip
  end

  field :url do
    member_url
  end

  private

  attr_reader :row, :url

  def tds
    @tds ||= row.css('td')
  end

  def member_url
    URI.join(url, row.at_css('a[href*="/Members/"]/@href').text).to_s
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
  ppm = PartyPage.new(url).to_h

  ppm[:members].each do |memrow|
    mp_noko = noko_for(memrow[:url])
    box = mp_noko.css('#mainform')
    memberships = box.xpath('.//strong[contains(.,"Member period")]/following-sibling::text()').map(&:text)

    data = { 
      id: memrow[:id],
      name: box.css('h1').text.strip,
      given_name: memrow[:given_name],
      family_name: memrow[:family_name],
      party: memrow[:party],
      party_id: CGI.parse(URI.parse(url).query)['party'].first.gsub(/[{}]/,''),
      constituency: memberships.first[/ in (.*?) from/, 1].sub('greater constituency','').strip,
      email: box.css('div.person a[href*="mailto:"]/@href').text.gsub('mailto:','').tr('|/',';'),
      homepage: box.css('div.person a[href*="http"]/@href').text,
      image: box.css('div.person img/@src').text,
      memberships: memberships.join("+++"),
      term: '2015',
      source: memrow[:url],
    }
    data[:image] = URI.join(memrow[:url], URI.escape(data[:image])).to_s unless data[:image].to_s.empty?
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
