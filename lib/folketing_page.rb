# frozen_string_literal: true

require 'scraped'

class FolketingPage < Scraped::HTML
  decorator Scraped::Response::Decorator::CleanUrls
end
