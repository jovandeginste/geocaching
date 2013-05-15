class CacheType
	include DataMapper::Resource
	property :id,   Serial
	property :name, String

	has n, :caches
end
