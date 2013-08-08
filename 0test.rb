require 'net/http'
require 'dm-core'
require 'dm-migrations'
require 'dm-mysql-adapter'
require 'dm-ar-finders'
require 'dm-types'

settings = YAML.load_file("settings.yaml")
database = settings[:database]
geocaching = settings[:geocaching]
paths = settings[:paths]

DataMapper::Logger.new($stdout, :debug)
DataMapper.setup(:default, database)

DataMapper::Inflector.inflections do |inflect|
	inflect.singular 'caches', 'cache'
end

Dir["./*.rb"].each {|file| require file.gsub(/\.rb$/, "") }

DataMapper.auto_upgrade!

HttpInterface.credentials = geocaching
Export.file_root_hash = paths
