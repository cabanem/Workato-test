#!/bin/bash
set -e
echo "🚀 Starting Workato Development Setup..."
gem list workato-connector-sdk -i > /dev/null 2>&1 || gem install workato-connector-sdk
[ -f Gemfile ] || cat > Gemfile << 'GEMFILE'
source 'https://rubygems.org'
gem 'workato-connector-sdk'
group :test do
  gem 'rspec', '~> 3.12'
  gem 'vcr', '~> 6.2'
  gem 'webmock', '~> 3.19'
end
group :development do
  gem 'pry'
  gem 'pry-byebug'
end
GEMFILE
[ -f Gemfile.lock ] || bundle install
echo "✅ Setup complete!"
