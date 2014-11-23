require 'rubygems'
require 'bundler/setup'

require 'date'

require 'redcarpet'

MD = Redcarpet::Markdown.new(
  Redcarpet::Render::HTML.new(:hard_wrap => true),
  :autolink => true,
  :no_intra_emphasis=>true,
  :space_after_headers => true
)

require 'mongo'
require 'uri'

if ENV['MONGOLAB_URI']
  uri  = URI.parse(ENV['MONGOLAB_URI'])
  MONGO = Mongo::MongoClient.from_uri(ENV['MONGOLAB_URI'])
  DB   = MONGO.db(uri.path.gsub(/^\//, ''))
else
  MONGO = Mongo::MongoClient.new
  DB  = MONGO['blog-dev']
end
GRID = Mongo::Grid.new(DB)
Posts = DB['posts']
Files = DB['fs.files']

require 'sinatra/base'

class Main < Sinatra::Base

  get '/' do
    @posts = Posts.find({published: true}, {
      fields: [:_id, :title, :summary, :thumbnail, :created_at, :published],
      sort: [[:date, :desc]]
    }).to_a
    erb :home
  end

  get '/:id' do
    @post = Posts.find_one(_id: params[:id], published: true)
    pass if @post.nil?
    @meta_title = @post['title']
    @meta_description = @post['summary']
    erb :post
  end

end

class Admin < Sinatra::Base

  enable :method_override

  unless ENV['PASSWORD'].nil?
    use Rack::Auth::Basic, 'Gates of Hell' do |username, password|
      password == ENV['PASSWORD']
    end
    before do
      redirect('/https-warning') unless request.scheme=='https'
    end
  end

  get '/' do
    @posts = Posts.find({}, {
      fields: [:_id, :title, :date, :thumbnail],
      sort: [[:date, :desc]]
    }).to_a
    @files = Files.find({},{sort: [[:upload_date, :desc]]}).to_a
    erb :admin_home
  end

  get '/post' do
    @post = {}
    erb :form_post
  end

  post '/post' do
    doc = params[:doc].dup
    doc['date'] = Date.strptime(doc['date'],'%Y-%m-%d').to_time.utc
    doc['thumbnail'] = detect_thumbnail doc['content']
    Posts.insert(doc)
    redirect('/admin')
  end

  get '/post/:id' do
    @post = Posts.find_one(_id: params[:id])
    pass if @post.nil?
    erb :form_post
  end

  put '/post/:id' do
    doc = params[:doc].dup
    doc['date'] = Date.strptime(doc['date'],'%Y-%m-%d').to_time.utc
    doc['thumbnail'] = detect_thumbnail doc['content']
    Posts.update({_id: params[:id]}, {'$set'=>doc})
    redirect('/admin')
  end

  delete '/post/:id' do
    Posts.remove({_id: params[:id]})
    redirect('/admin')
  end

  get '/file' do
    erb :form_file
  end

  post '/file' do
    doc = params[:doc].dup
    id = doc['file'][:filename].sub(/\.[^.]*$/,'')
    GRID.put(doc['file'][:tempfile],{
      _id: id,
      filename: doc['file'][:filename],
      content_type: doc['file'][:type],
      chunk_size: 100*1024,
      metadata: {description: doc['description']}
    })
    redirect('/admin')
  end

  delete '/file/:id' do
    GRID.delete(params[:id])
    redirect('/admin')
  end
  
  get '/https-warning' do
    erb :https_warning
  end

  helpers do
    def detect_thumbnail s
      s.to_s=~/!\[[^\]]*\]\(([^\)]*)\)/ ? $1 : nil
    end
  end

end

require 'rack/gridfs'
use ::Rack::GridFS, db: DB, prefix: 'file', lookup: :path
map '/admin' do run Admin end
map '/' do run Main end

