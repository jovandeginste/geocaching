require 'net/http'
require 'openssl'

class HttpInterface
	class << self
		def credentials
			@credentials
		end

		def credentials=(credentials)
			@credentials = credentials
		end
		def https_instance
			@https_instance
		end

		def https_instance=(instance)
			@https_instance = instance
		end
		def http_instance
			@http_instance
		end

		def http_instance=(instance)
			@http_instance = instance
		end

		def headers
			if defined?(@headers)
				@headers
			elsif superclass != Object && superclass.headers
				superclass.headers
			else
				@headers ||= {}
			end
		end

		def authentication
			puts "Authenticating..."
			authuri = "/login/default.aspx?redir=%2fmap%2fdefault.aspx%3f"
			credentials = {
				"__EVENTTARGET" => "",
				"__EVENTARGUMENT" => "",
				"__VIEWSTATE" => "",
				"__VIEWSTATEGENERATOR" => "",
				#"__PREVIOUSPAGE" => "Kz_QjFpkXxJ0V2-727Am3pSAtsCKPUapMQA-xu1p5mQCR6mH0bNiCeWfFpXklcRnE-aZ8-XLAR2_kOC8l-nRlYp7y781",
				"ctl00$ContentBody$tbUsername" => self.credentials[:username],
				"ctl00$ContentBody$tbPassword" => self.credentials[:password],
				"ctl00$ContentBody$btnSignIn" => "Sign In",
				"ctl00$ContentBody$tbSearch" => "postal code, country, etc",
				"_a"=>"_b",
			}

			# We doen een post naar 'authuri' om in te loggen met de credentials
			resp = self.https_instance.post(authuri, URI.encode_www_form(credentials))
			# 302 is redirect (naar destination => resturi), dus success
			if resp.code == "302"
				puts "Authenticated!"
				self.headers["Cookie"] = resp.response['set-cookie'].split(/,[[:space:]]*/).join("; ")
			else
				puts "Something went wrong while authenticating..."
				false
			end
			resp
		end
	end

	def post_page(page, data, proto = "http")
		self.class.post_page(page, data, proto)
	end
	def self.post_page(page, data, proto = "http")
		self.authentication if self.headers.empty?
		instance = case proto
			   when "http"
				   self.http_instance
			   else
				   self.https_instance
			   end
		resp = nil
		until resp
			begin
				resp = instance.post(page, URI.encode_www_form(data), self.headers)
			rescue Errno::ECONNRESET
				puts "Connection reset - try again!"
				sleep 0.3
			end
		end
		if !self.is_authenticated?(resp.body)
			if !self.authentication
				posts "Authentication failed!"
			end
			resp = instance.post(page, URI.encode_www_form(data), self.headers)
		end
		resp
	end
	def get_page(page, proto = "http")
		self.class.get_page(page, proto)
	end
	def self.get_page(page, proto = "http")
		self.authentication if self.headers.empty?
		instance = case proto
			   when "http"
				   self.http_instance
			   else
				   self.https_instance
			   end
		resp = nil
		until resp
			begin
				resp = instance.get(page, self.headers)
			rescue Errno::ECONNRESET
				puts "Connection reset - try again!"
				sleep 0.3
			end
		end
		resp = case resp
		       when Net::HTTPSuccess     then resp
		       when Net::HTTPRedirection then
			       location = resp['location']
			       if location.match(/^https?:\/\//)
				       proto, location = location.split("://")
				       location = location.gsub(/^[^\/]+/, "")
			       end
			       return self.get_page(location, proto)
		       else
			       resp
		       end
		if !self.is_authenticated?(resp.body)
			if !self.authentication
				puts "Authentication failed!"
			end
			resp = instance.get(page, self.headers)
		end
		resp
	end
	def is_authenticated?(body = "")
		self.class.is_authenticated?(body)
	end
	def self.is_authenticated?(body = "")
		return true if !body.match(/<kml .*>/).nil?
		return true if !body.match(/SignedInProfileLink/).nil?
		return true if !body.match(/^var lat=.*lng=/).nil?
		return true if !body.match(/"status":"success"/).nil?
	end

	self.http_instance = Net::HTTP.new("www.geocaching.com", 80)
	self.https_instance = Net::HTTP.new("www.geocaching.com", 443)
	self.https_instance.use_ssl = true
	self.https_instance.verify_mode = OpenSSL::SSL::VERIFY_NONE
end
