class CacheList
	include DataMapper::Resource
	property :id,   Serial
	property :guid, String, :unique => true, :required => true
	property :name, String, :required => true
	property :last_update, DateTime

	belongs_to :owner, 'Cacher', :required => true
	has n, :caches, :through => Resource

	before :save do
		if self.last_update.nil? or DateTime.now > self.last_update + 30
			self.update_from_site
		end
	end

	def update_from_site
		self.attributes = self.data_from_site
	end

	def update_from_site!
		self.update self.data_from_site
	end

	def data_from_site
		body = self.get_html

		result = {}
		owner_guid = body.find{|line| line.match(/\/profile\//)}.gsub(/.*guid=/, "").gsub(/".*/, "")
		result[:owner] = Cacher.find_or_create(guid: owner_guid)
		result[:name] = body.find{|line| line.match(/"ctl00_ContentBody_lbHeading"/)}.gsub(/>Edit</, "").remove_tags.strip
		result[:last_update] = DateTime.now
		result
	end

	def update_caches_from_site
		self.caches_from_site.each{|cache|
			self.caches << Cache.find_or_create(guid: cache)
		}
		self.last_update = DateTime.now
		self.save
	end
	def caches_from_site
		body = self.get_kml.select{|line| line.match(/guid=/)}.collect{|line| line.gsub(/.*guid=/, "").gsub(/'.*/, "")}
	end

	def get_kml
		url = "/kml/bmkml.aspx?bmguid=" + self.guid
		request = HttpInterface.get_page(url)
		request.body.force_encoding("UTF-8").split("\r\n")
	end
	def get_html
		url = "/bookmarks/view.aspx?guid=" + self.guid
		request = HttpInterface.get_page(url)
		request.body.force_encoding("UTF-8").gsub(/\r\n/, "\n").split("\n")
	end

	def to_s
		"#{self.name} (#{self.guid})"
	end
end
