#!/usr/bin/env ruby
require 'redmine2things'

r2t = Redmine2Things.new(
  # all redmine parameters are required
  { :site => 'http://demo.redmine.org', :user => 'user', :password => 'password', :user_id => 1 },
  # all Things parameters are optional
  { :area => 'Work', :tags => 'Work' }
)

# run syncing
r2t.sync

