# frozen_string_literal: true

require_relative 'folketing_page'

class MemberPage < FolketingPage
  field :name do
    box.css('h1').map(&:text).map(&:tidy).first
  end

  field :constituency do
    raw_memberships.first.to_s[/ in (.*?) from/, 1].to_s.sub('greater constituency', '').tidy
  end

  field :email do
    box.css('div.person__container__contactinfo a[href*="mailto:"]/@href').map(&:text).map { |e| e.gsub('mailto:', '').tr('|/', ';') }.uniq.join(';')
  end

  field :image do
    # there's probably a better way to get all the URL minus the query
    displayed_image.to_s.chomp(displayed_image.query)
  end

  field :birthdate do
    return unless birthline
    Date.parse(birthline).to_s rescue binding.pry
  end

  field :facebook do
    websites.select { |url| url.include? 'facebook' }.join(';')
  end

  field :twitter do
    websites.select { |url| url.include? 'twitter' }.join(';')
  end

  field :homepage do
    websites.reject { |url| url.include?('facebook') || url.include?('twitter') }.join(';')
  end

  private

  def box
    noko.css('.person__container')
  end

  def raw_memberships
    noko.xpath('.//strong[contains(.,"Member period")]/following-sibling::text()').map(&:text)
  end

  def websites
    box.css('div.person__container__contactinfo a[href*="http"]/@href').map(&:text)
  end

  def birthline
    noko.css('.ftMember__accordion__container').map(&:text).flat_map(&:lines).find { |text| text.downcase.include? 'born' }
  end

  # this is cut down to size with a parameter
  def displayed_image
    URI.parse box.css('img.bio-image/@src').text
  end
end
