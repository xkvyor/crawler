#encoding=utf-8

require 'open-uri'
require 'uri'
require 'timeout'
require 'sqlite3'
require 'digest'

## define constants ##

$_TIME_OUT_ = 10

$_MAX_URL_LENGTH_ = 512
$_MAX_PAGE_CACHE_ = 5000
$_MAX_VISITED_LIST_LENGTH = 10000

$_IMAGES_PATH_ = './images/'

$_DATABASE_ = nil
$_DATABASE_NAME_ = 'test2.db'
$_URL_TABLE_ = 'url'
$_IMG_TABLE_ = 'img'

$_WORD_LIST_ = %W{
  \u6027\u611f \u7f8e\u5973 \u5de8\u4e73
}

## end ##

def log(message)
	filename = Time.now.to_s.split(' ')[0] + '_v2.log'
	message = "[#{Time.now}] #{message}"
	if File.exist?(filename)
		open(filename, 'a') do |f|
			f.puts(message)
		end
	else
		f = File.new(filename, 'w')
		f.puts(message)
	end
end

def err_log(message)
	filename = Time.now.to_s.split(' ')[0] + '_error_v2.log'
	message = "[#{Time.now}] #{message}"
	if File.exist?(filename)
		open(filename, 'a') do |f|
			f.puts(message)
		end
	else
		f = File.new(filename, 'w')
		f.puts(message)
	end
end

def md5(str)
	return Digest::MD5.hexdigest(str)
end

def set_url(path, url)
	URI.parse(url).merge(path).to_s
end

def get_links(page, url)
	links = []
	page.scan(/<a\b[^>]*?href=['"](.*?)['"].*?>/) do |link|
		link = link[0]
		link = set_url(link, url) unless link.index('http://') == 0
		links << link
	end
	return links
end

def get_imgs(page, url)
	imgs = []
	page.scan(/<img\b[^>]*?src=['"](.*?)['"].*?>/) do |img|
		img = img[0]
		img = set_url(img, url) unless img.index('http://') == 0
		imgs << img
	end
	return imgs
end

def get_index(page)
	index = []
	$_WORD_LIST_.each do |word|
		i = 0
		page.scan(word) { i += 1 }
		index << i
	end
	return index.join(',')
end

def visited?(url)
	rs = $_DATABASE_.execute("select * from #{$_URL_TABLE_} where url='#{url}'");
	return rs.length > 0 ? true : false
end

def init
	$_DATABASE_ = SQLite3::Database.open $_DATABASE_NAME_
end

def release
	$_DATABASE_.close() if $_DATABASE_
end

def save_link(url)
	$_DATABASE_.execute("insert into #{$_URL_TABLE_} values('#{url}')");
end

def save_img(img)
	open(img) do |file|
		ext = file.meta['content-type'].split(';')[0].split('/')[1]
		File.open("#{$_IMAGES_PATH_}#{md5(img)}.#{ext}", 'wb') do |o|
			o.puts file.read
		end
	end
end

def merge_index(idx1, idx2)
	index1 = idx1.split(',')
	index2 = idx2.split(',')
	index = []
	0.upto(index1.length-1) do |i|
		index << (index1[i].to_i + index2[i].to_i)
	end
	return index.join(',')
end

def process_img(img, index)
	rs = $_DATABASE_.execute("select * from #{$_IMG_TABLE_} where url='#{img}'");
	if rs.length > 0
		ref = rs[0][1] + 1
		idx = rs[0][2]
		idx = merge_index(idx, index)
		$_DATABASE_.execute("update #{$_IMG_TABLE_} set ref=#{ref},idx='#{idx}' where url='#{rs[0][0]}'");
	else
		$_DATABASE_.execute("insert into #{$_IMG_TABLE_} values('#{img}', 1, '#{index}')");
		save_img(img)
	end
end

def crawl(pages, depth)
	0.upto(depth) do
		newpages = []
		pages.each do |url|
			begin
				raise "url #{url} is too long" if url.length > $_MAX_URL_LENGTH_
				next if visited?url
				
				# crawl
				content = ''
				Timeout::timeout($_TIME_OUT_) do
					open(url) do |file|
						content =  file.readlines.join
						content = content.encode('utf-8', file.charset(), :invalid => :replace, :undef => :replace)
					end
				end
				save_link(url)
				# analyze
				links = get_links(content, url)
				imgs = get_imgs(content, url)
				index = get_index(content)
				# new links
				links.each do |link|
					newpages << link
				end
				# new imgs
				imgs.each do |img|
					process_img(img, index)
				end
			rescue Exception => e
				err_log(e)
			end
		end
		pages = newpages
	end
end

pagelist = [
	# 'http://www.baidu.com/',
	# 'http://www.sohu.com',
	# 'http://www.163.com',
	'http://www.javblog.org',
	# 'http://www.bilibili.tv/',
	'http://www.17173.com/',
]

begin
	init()
	crawl(pagelist, 3)
rescue Exception => e
	err_log(e)
ensure
	release()
end
