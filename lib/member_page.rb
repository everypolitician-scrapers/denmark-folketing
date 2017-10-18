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
    box.css('div.person a[href*="mailto:"]/@href').map(&:text).map { |e| e.gsub('mailto:', '').tr('|/', ';') }.uniq.join(';')
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
