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
Posts = DB['posts']

require 'sinatra/base'

class Main < Sinatra::Base

  get '/' do
    @posts = Posts.find({published: true}, {
      fields: [:_id, :title, :summary, :created_at, :published],
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
    redirect('/admin/posts')
  end

  get '/posts' do
    @posts = Posts.find({}, {
      fields: [:_id, :title, :date],
      sort: [[:date, :desc]]
    }).to_a
    erb :admin_home
  end

  get '/post' do
    @post = {}
    erb :form_post
  end

  post '/post' do
    doc = params[:doc].dup
    doc['date'] = Date.strptime(doc['date'],'%Y-%m-%d').to_time.utc
    Posts.insert(doc)
    redirect('/admin/posts')
  end

  get '/post/:id' do
    @post = Posts.find_one(_id: params[:id])
    pass if @post.nil?
    erb :form_post
  end

  put '/post/:id' do
    doc = params[:doc].dup
    doc['date'] = Date.strptime(doc['date'],'%Y-%m-%d').to_time.utc
    Posts.update({_id: params[:id]}, {'$set'=>doc})
    redirect('/admin/posts')
  end

  delete '/post/:id' do
    Posts.remove({_id: params[:id]})
    redirect('/admin/posts')
  end
  
  get '/https-warning' do
    erb :https_warning
  end

end

map '/admin' do run Admin end
map '/' do run Main end

