#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'

# require 'open-uri/cached'
# OpenURI::Cache.cache_path = '.cache'
require 'scraped_page_archive/open-uri'

class FolketingPage < Scraped::HTML
  decorator Scraped::Response::Decorator::AbsoluteUrls
end

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
    new_args = URI.decode_www_form(uri.query || '') << %w(pagesize 100)
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

class MemberPage < FolketingPage
  field :name do
    box.css('h1').text.tidy
  end

  field :constituency do
    raw_memberships.first.to_s[/ in (.*?) from/, 1].to_s.sub('greater constituency', '').tidy
  end

  field :email do
    box.css('div.person a[href*="mailto:"]/@href').text.gsub('mailto:', '').tr('|/', ';')
  end

  field :homepage do
    box.css('div.person a[href*="http"]/@href').text
  end

  field :image do
    box.css('div.person img/@src').text
  end

  field :memberships do
    raw_memberships.join('+++')
  end

  private

  def box
    noko.css('#mainform')
  end

  def raw_memberships
    box.xpath('.//strong[contains(.,"Member period")]/following-sibling::text()').map(&:text)
  end
end

module EveryPolitician
  class ScraperRun
    def initialize(id: SecureRandom.uuid, table: 'data', index_fields: nil, default_index_fields: %i(id term))
      @run_data = { id: id, started: Time.now }
      @table = table
      @index_fields = index_fields
      @default_index_fields = default_index_fields
      ScraperWiki.save_sqlite(%i(id), run_data, 'runs')
      ScraperWiki.sqliteexecute('DELETE FROM %s' % table) rescue nil
    end

    def save_all(data, debugging: ENV['MORPH_PRINT_DATA'])
      data.each { |r| puts r.reject { |_, v| v.to_s.empty? }.sort_by { |k, _| k }.to_h } if debugging
      ScraperWiki.save_sqlite(index_fields_from(data), data, table)
      ScraperWiki.save_sqlite(%i(id), run_data.merge(ended: Time.now), 'runs')
    end

    def error(e)
      ScraperWiki.save_sqlite(%i(id), run_data.merge(errored: Time.now), 'runs')
      # TODO: do something better with the error
      raise e
    end

    private

    attr_reader :run_data, :table, :index_fields, :default_index_fields

    def index_fields_from(data)
      index_fields || (data.first.keys & default_index_fields)
    end
  end

  class Scraper
    def initialize(url:, default_data: {})
      @url = url
      @default_data = default_data
    end

    def run
      scraper_run.save_all(data)
    rescue => e
      scraper_run.error(e)
    end

    private

    attr_reader :url, :default_data

    def scraper_run
      @scraper_run = EveryPolitician::ScraperRun.new
    end

    def scrape(h)
      url, klass = h.to_a.first
      klass.new(response: Scraped::Request.new(url: url).response)
    end
  end
end

def scrape(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

start = 'http://www.thedanishparliament.dk/Members/Members_in_party_groups.aspx'

ScraperWiki.sqliteexecute('DELETE FROM data') rescue nil
scrape(start => PartiesPage).parties.each do |party|
  scrape(party.url => PartyPage).members.each do |memrow|
    mem = scrape(memrow.source => MemberPage)
    data = memrow.to_h.merge(mem.to_h).merge(term: '2015')
    # puts data.reject { |k, v| v.to_s.empty? }.sort_by { |k, v| k }.to_h
    ScraperWiki.save_sqlite(%i(id term), data)
  end
end
