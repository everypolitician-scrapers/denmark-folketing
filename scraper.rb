#!/bin/env ruby
# encoding: utf-8

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

  def absolute_url(rel)
    return if rel.to_s.empty?
    URI.join(url, URI.encode(URI.decode(rel)))
  end
end

class PartiesPage < Page
  field :parties do
    noko.css('.telbogTable tr a[href*="party="]').map do |a|
      {
        name: a.text,
        url:  add_pagesize(absolute_url(a.attr('href'))).to_s,
      }
    end
  end

  private

  # We want to add a default '?pagesize=100' to all links
  def add_pagesize(uri)
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
  require 'cgi'

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

  field :party_id do
    CGI.parse(URI.parse(url).query)['party'].first.gsub(/[{}]/,'')
  end

  field :source do
    member_url.to_s
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

class MemberPage < Page
  field :name do
    box.css('h1').text.strip
  end

  field :constituency do
    memberships.first[/ in (.*?) from/, 1].sub('greater constituency','').strip
  end

  field :email do
    box.css('div.person a[href*="mailto:"]/@href').text.gsub('mailto:','').tr('|/',';')
  end

  field :homepage do
    box.css('div.person a[href*="http"]/@href').text
  end

  field :image do
    absolute_url(box.css('div.person img/@src').text).to_s
  end

  field :memberships do
    memberships.join("+++")
  end

  private

  def box
    noko.css('#mainform')
  end

  def memberships
    box.xpath('.//strong[contains(.,"Member period")]/following-sibling::text()').map(&:text)
  end
end

def scrape_party_list(url)
  PartiesPage.new(url).to_h[:parties].each do |party|
    scrape_party party[:url]
  end
end

def scrape_party(url)
  ppm = PartyPage.new(url).to_h

  ppm[:members].each do |memrow|
    mem = MemberPage.new(memrow[:source])
    data = memrow.merge(mem.to_h).merge(term: '2015')
    ScraperWiki.save_sqlite([:id, :term], data)
  end
end

scrape_party_list('http://www.thedanishparliament.dk/Members/Members_in_party_groups.aspx')
