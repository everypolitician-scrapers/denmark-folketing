#!/bin/env ruby
# encoding: utf-8
# frozen_string_literal: true

require 'pry'
require 'scraped'
require 'scraperwiki'

require 'open-uri/cached'
OpenURI::Cache.cache_path = '.cache'
# require 'scraped_page_archive/open-uri'

def scrape(h)
  url, klass = h.to_a.first
  klass.new(response: Scraped::Request.new(url: url).response)
end

class PartiesPage < Scraped::HTML
  decorator Scraped::Response::Decorator::AbsoluteUrls

  field :parties do
    noko.css('.telbogTable tr a[href*="party="]').map do |a|
      {
        name: a.text,
        url:  add_pagesize(a.attr('href')).to_s,
      }
    end
  end

  private

  # We want to add a default '?pagesize=100' to all links
  def add_pagesize(url)
    uri = URI.parse(url)
    new_args = URI.decode_www_form(uri.query || '') << %w(pagesize 100)
    uri.query = URI.encode_www_form(new_args)
    uri.to_s
  end
end

class PartyPage < Scraped::HTML
  decorator Scraped::Response::Decorator::AbsoluteUrls

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
    tds[0].text.strip
  end

  field :family_name do
    tds[1].text.strip
  end

  field :party do
    tds[2].text.strip
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

class MemberPage < Scraped::HTML
  decorator Scraped::Response::Decorator::AbsoluteUrls

  field :name do
    box.css('h1').text.strip
  end

  field :constituency do
    # TODO this isn't quite right yet
    raw_memberships.first.to_s[/ in (.*?) from/, 1].to_s.sub('greater constituency', '').strip
  end

  field :email do
    box.css('div.person a[href*="mailto:"]/@href').text.gsub('mailto:', '').tr('|/', ';')
  end

  field :homepage do
    box.css('div.person a[href*="http"]/@href').text
  end

  field :image do
    img = box.css('div.person img/@src').text
    binding.pry if img.start_with? '~'
    img
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

def scrape_party(url)
  members = scrape(url => PartyPage).members
  # raise "No members in #{url}" unless members.any?
  members.each do |memrow|
    mem = scrape(memrow.source => MemberPage)
    data = memrow.to_h.merge(mem.to_h).merge(term: '2015')
    puts data
    # ScraperWiki.save_sqlite(%i(id term), data)
  end
end

start = 'http://www.thedanishparliament.dk/Members/Members_in_party_groups.aspx'
parties = scrape(start => PartiesPage).parties
raise "No parties to scrape" unless parties.any?
parties.each { |party| scrape_party party[:url] }
