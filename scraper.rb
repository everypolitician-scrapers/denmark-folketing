#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'

require_rel 'lib'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'
# require 'scraped_page_archive/open-uri'

class PartiesPage < FolketingPage
  field :parties do
    noko.css('.telbogTable tr a[href*="party="]').map do |a|
      fragment a => PartiesPageParty
    end
  end
end

class PartiesPageParty < Scraped::HTML
  field :name do
    noko.text
  end

  field :url do
    # We want to add a default '?pagesize=100'
    # TODO: make this a decorator
    uri = URI.parse(original_url)
    new_args = URI.decode_www_form(uri.query || '') << %w[pagesize 100]
    uri.query = URI.encode_www_form(new_args)
    uri.to_s
  end

  private

  def original_url
    noko.attr('href')
  end
end

class PartyPage < FolketingPage
  field :members do
    noko.css('.telbogTable').xpath('.//tr[td]').map do |tr|
      fragment tr => PartyPageMember
    end
  end
end

class PartyPageMember < Scraped::HTML
  require 'cgi'

  field :id do
    source.to_s[%r{/Members/(.*).aspx}, 1]
  end

  field :given_name do
    tds[0].text.tidy
  end

  field :family_name do
    tds[1].text.tidy
  end

  field :party do
    tds[2].text.tidy
  end

  field :party_id do
    CGI.parse(URI.parse(url).query)['party'].first.gsub(/[{}]/, '')
  end

  field :source do
    noko.at_css('a[href*="/Members/"]/@href').text
  end

  private

  def tds
    noko.css('td')
  end
end

def scraper(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

start = 'http://www.thedanishparliament.dk/Members/Members_in_party_groups.aspx'

data = scraper(start => PartiesPage).parties.flat_map do |party|
  scraper(party.url => PartyPage).members.map do |memrow|
    mem = scraper(memrow.source => MemberPage)
    memrow.to_h.merge(mem.to_h).merge(term: '2015')
  end
end
data.each { |mem| puts mem.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if ENV['MORPH_DEBUG']

ScraperWiki.sqliteexecute('DROP TABLE data') rescue nil
ScraperWiki.save_sqlite(%i[id term], data)
