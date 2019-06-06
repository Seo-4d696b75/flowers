# いろいろスクリプト
#@date 2019/05/22
#@author B4仙田薫  Seo-4d696b75
#
#(1) URLリストのJPG画像をまとめて落とす
# 複数のスレッドを用いて並列処理するから少しは早いはず
# 使い方： "ruby utils.rb --get {url_list} {thread_size} [{des_dir} {ca_file}]"
#   url_list: 各画像へのURLが改行区切りで保存されたファイルのパス
#   thread_size: 並列処理させるスレッドの数 10くらいで
#   des_dir: ダウンロードしたファイルの保存先ディレクトリ 未指定時はカレントディレクトリ
#   ca_file: 証明書（指定する場合）
# 出力：
#   des_dir以下に落とされた画像
#   カレントディレクトリ以下にlog.txt
#
# log.txtに"certificate verify failed  (OpenSSL::SSL::SSLError)"と出力されて
# HTTPS通信が失敗するのであれば
# 証明書を別に用意 source: http://curl.haxx.se/ca/cacert.pem
# （もしくはRubyを更新）
#
#(2) データセットの分割
# https://cloud.google.com/ml-engine/docs/tensorflow/flowers-tutorial?hl=ja
# で説明されている5種類の花の画像リストに1種類以上の花を追加して
# 新しい学習・テスト用の画像リストを作る
# 使い方： "ruby utils.rb --split {dir1} [{dir2}...]"
#   dir: 同一ラベルの画像が収められたディレクトリへのパス
#        このディレクトリ名をそのままラベル名と解釈するので相対パス
# 出力：カレントディレクトリ下に
#   eval_set.csv 
#   train_set.csv
#   eval_set_source.csv 元のヤツ
#   train_set_source.csv 元のヤツ
#   {ラベル名}_list.txt 各ラベルごとの画像ファイル一覧
# 
require 'net/http'
require 'openssl'

def format_dir(des)
	if des==nil || des.empty?
		return './'  
	end
	des = des.gsub('\\','/')
	if des[0] == '/'
		if des == '/' then raise "root directory not accepted." end
		des = des[1..-1]
	end
	if des.length > 2 && des[0,2] == './'
		des = des[2..-1]
	end
	if des[-1] != '/'
		return des + '/'
	else
		return des
	end
end


# How to use?
# (1) get instance like: " a = AutoLoader.new({url_list},{thread_size},[{des_dir},{ca_file}])"
# (2) let it run!  : " a.load() "
# (3) its progress will be shown and more details writen into "log.txt" 
class AutoLoader

	#
	#@param src URLリストのファイル
	#@param size threadの数
	#
	def initialize(src, size, des, ca)
		@des = format_dir(des)
		@ca = ca
		@queue = []
		File.open(src) do |file|
			file.each_line do |line|
				@queue.push(line.chomp!)
			end
		end
		@num = size
		@queue_mutex = Mutex.new
		@log_mutex = Mutex.new
		@result_mutex = Mutex.new
	end

	def get(path)
		begin
		m = path.match(/^((http|https):\/\/.+?(\/.+\.(jpg|JPG)))/)
		return nil if m == nil
		uri = URI.parse(URI.encode(m[1]))
		if m[2] == "http"
			return Net::HTTP.get_response(uri)
		elsif m[2] == "https"
			https = Net::HTTP.new(uri.host, uri.port)
			https.use_ssl = true
			https.verify_mode = OpenSSL::SSL::VERIFY_PEER
			https.verify_depth = 5
			if @ca then https.ca_file = @ca end
			response = https.start { |w| w.get(m[3]) }
			return response
		end
		rescue => e
			log e.class
			log e.message
		end
		return nil
	end

	def load()
		threads = []
		@log = open("log.txt", "w")
		@success = 0
		@cnt = 0
		@size = @queue.length
		print "start..."
		for i in 0..@num
			thread = Thread.new do
				while e = dequeue
					r = process(e)
					on_processed(r)
				end
			end
			threads.push(thread)
		end
		threads.each{|t| t.join}
		log("All done.")
		@log.close
		puts "\nAll done."
	end

	def process(path)
		if m = path.match(/^.+\/(.+?)\.(jpg|JPG)/)
			name = @des + m[1] + ".jpg"
			index = 1
			while File.exist?(name)
				name = "#{@des}#{m[1]}_#{index}.jpg"
				index += 1
			end
			response = get(path)
			if response != nil && (response.code == "301" || response.code == "302")
				location = response["location"]
				if location.match(/^.+\.(jpg|JPG)$/)
					path = location
				elsif location.match(/^(http|https):\/\/[^\/]+$/)
					path = path.sub(/^(http|https):\/\/.+?(?=\/)/, location)
				elsif location.match(/^(http|https):\/\/[^\/]+\/$/)
					path = path.sub(/^(http|https):\/\/.+?\//, location)
				else
					log "Erro > unknown #{location}"
					return false
				end
				log "Log > redirect to #{path}"
				response = get(path)
			end
			if response == nil
				log "Error > #{path}"
			elsif response.code == "200" 
				#JPEG については、ファイルが 
				#"0xFF 0xD8" で始まり、"0xFF 0xD9" で終わることをチェック
				# HTTP status 200 でも画像以外のファイルが返される場合あり
				img = response.body
				if [0xFF,0xD8].pack("C*") == img[0,2] && [0xFF,0xD9].pack("C*") == img[-2,2]
					out = open(name, "wb")
					out.write(img)
					out.close
					log "Success > #{path}"
					return true
				else
					log "Error > file broken #{path}"
				end
			else
				log "Error > #{response.code} #{path}"
			end
		end
		return false
	end
	
	def on_processed(result)
		@result_mutex.synchronize do
			@cnt += 1
			if result then @success += 1 end
			print "\r  #{(100.0*@cnt/@size).to_i}%  success:#{@success}/#{@cnt}"
		end
	end

	def dequeue()
		@queue_mutex.synchronize{ return @queue.shift }
	end

	def log(mes)
		@log_mutex.synchronize{ @log.puts(mes) }
	end

end

FILE_DICT = "dict_source.txt"
FILE_EVAL = "eval_set_source.csv"
FILE_TRAIN = "train_set_source.csv"

if ARGV[0] == "--get"
	list = ARGV[1]
	size = ARGV[2].to_i
	puts "download images > URL list:#{list} thread size:#{size}"
	loader = AutoLoader.new(list, size, ARGV[3], ARGV[4])
	loader.load()
elsif ARGV[0] == "--split"
	puts "split dataset..."
	if !File.exist?(FILE_DICT) 
		system("gsutil cp gs://cloud-ml-data/img/flower_photos/dict.txt #{FILE_DICT}")
	end
	if !File.exist?(FILE_EVAL)
		system("gsutil cp gs://cloud-ml-data/img/flower_photos/eval_set.csv #{FILE_EVAL}")
	end
	if !File.exist?(FILE_TRAIN)
		system("gsutil cp gs://cloud-ml-data/img/flower_photos/train_set.csv #{FILE_TRAIN}")
	end
	train = []
	File.open(FILE_TRAIN,"r"){|f| f.each_line{|l| train << l.chomp}}
	eval = []
	File.open(FILE_EVAL,"r"){|f| f.each_line{|l| eval << l.chomp}}
	labels = []
	File.open(FILE_DICT,"r"){|f| f.each_line{|l| labels << l.chomp}}
	ARGV.map{|name| format_dir(name)}.select{|name| Dir.exist?(name)}.each do |dir|
		list = Dir.glob("#{dir}*.jpg")
		label = dir[0..-2]
		labels << label
		File.open("#{label}_list.txt","w"){|f| list.each{|item| f.puts(item)}}
		puts "label:#{label} size:#{list.length}"
		list.shuffle!
		for i in 1..(list.length/11)
			eval << "#{list.shift},#{label}"
		end
		list.each{|item| train << "#{item},#{label}"}
	end
	File.open("dict.txt","w"){|f| labels.each{|label| f.puts(label)}}
	File.open("eval_set.csv","w"){|f| eval.each{|e| f.puts(e)}}
	File.open("train_set.csv","w"){|f| train.each{|e| f.puts(e)}}
end
