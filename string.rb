require 'i18n'
class String
	def remove_tags
		self.gsub(/<[^>]*>/, '')
	end
	def strip_tags
		self.sub(/^<[^>]*>/, "").sub(/<[^>]*>$/, "")
	end
	def remove_spaces
		self.gsub(/[[:space:]]/, '')
	end
	def substitude_urls
		self.gsub(/src=(["'])([^h][^t][^t][^p][^s]?[^:])/, 'src=\1http://www.geocaching.com/seek/\2').gsub(/\/seek\/\//, "/").gsub(/\/seek\/\.\.\//, "/")
	end
	def rot13
		self.rot(13)
	end
	def rot(nr = 13)
		self.each_byte.map do |byte|
			case byte
			when 97..122
				byte = ((byte - 97 + nr) % 26) + 97
			when 65..90
				byte = ((byte - 65 + nr) % 26) + 65
			end
			byte
		end.pack('c*')
	end

	def transliterate
		I18n.transliterate(self)
	end

	def self.new_from_editor
		tmp = Tempfile.new("edit")
		system(ENV['EDITOR'] + ' ' + tmp.path)
		new_string = tmp.read
		tmp.delete
		return new_string
	end
	def edit
		tmp = Tempfile.new("edit")
		tmp.write self
		tmp.rewind
		system(ENV['EDITOR'] + ' ' + tmp.path)
		new_string = tmp.read
		tmp.delete
		new_string
	end
end
