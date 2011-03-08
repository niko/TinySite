require 'rspec'
$LOAD_PATH << File.join(File.dirname(File.expand_path __FILE__), '../lib')

require 'tiny_site'

describe TextileParts do
  before do
    @t = <<-EOT
---
:a: bla
:e: ble
++++navigation++++
* "one":eins
* "two":zwei
++++body++++
h1. header
EOT
  end
  describe ".image_url_for" do
    it "delegates to the app" do
      @app = stub(:app)
      TextileParts.parse(@t, @app)
      @app.should_receive(:image_url_for).with('foobar.png')
      TextileParts.image_url_for('foobar.png')
    end
  end
  describe ".parse" do
    before(:each) do
      @app = stub(:app)
    end
    it 'gets the variables' do
      TextileParts.parse(@t, @app).should == {
        :a => 'bla',
        :e => 'ble',
        'navigation' => %Q{<ul>\n\t<li><a href="eins">one</a></li>\n\t<li><a href="zwei">two</a></li>\n</ul>},
        'body' => %Q{<h1>header</h1>}
      }
    end
    it "returns a 404 title when passed nil" do
      TextileParts.parse(nil, @app).should == {:title => '404 not found'}
    end
  end
  describe ".textilize" do
    before(:each) do
      @app = stub(:app, :image_url_for => 'some/image.png')
    end
    describe "images relative path" do
      it "uses the images path" do
        TextileParts.should_receive(:image_url_for).and_return('some/image.png')
        s = "bla bla !an_image.jpg! blable"
        TextileParts.textilize(s).should == %Q{<p>bla bla <img src="some/image.png" alt="" /> blable</p>}
      end
    end
    describe "images absolute path" do
      it "leaves them alone" do
        s = "bla bla !/an_image.jpg! blable"
        TextileParts.textilize(s).should == %Q{<p>bla bla <img src="/an_image.jpg" alt="" /> blable</p>}
      end
    end
    describe "images absolute path, domain and protocol" do
      it "leaves them alone" do
        s = "bla bla !http://foo.bar/an_image.jpg! blable"
        TextileParts.textilize(s).should == %Q{<p>bla bla <img src="http://foo.bar/an_image.jpg" alt="" /> blable</p>}
      end
    end
  end
end

describe CachedHttpFile do
  describe '#fetch' do
    it 'gets the url' do
      uri = URI.parse 'http://foo/bar'
      f = CachedHttpFile.new uri
      OpenURI.should_receive(:open_uri).with(uri).and_return(StringIO.new)
      f.fetch
    end
    it 'returns the content of the file and the status 200' do
      f = CachedHttpFile.new 'http://foo/bar'
      OpenURI.stub! :open_uri => StringIO.new('foo')
      f.fetch.should == [200, 'foo']
    end
    it 'it catches http errors and returns the status' do
      f = CachedHttpFile.new 'http://foo/bar'
      OpenURI.should_receive(:open_uri).and_raise(OpenURI::HTTPError.new '485 Ugly client', '')
      f.fetch.should == [485, nil]
    end
    it "stores the body" do
      f = CachedHttpFile.new 'http://foo/bar'
      OpenURI.stub! :open_uri => StringIO.new('foo')
      now = Time.now
      Time.stub! :now => now
      CachedHttpFile.files['http://foo/bar'][:content].should == 'foo'
      CachedHttpFile.files['http://foo/bar'][:expires_at].should be_a(Time)
    end
  end
  describe "the caching" do
    it "expires" do
      f = CachedHttpFile.new 'http://foo/bar', 0.1
      OpenURI.stub! :open_uri => StringIO.new('foo')
      f.fetch
      f.cached?.should be_true
      sleep 0.1
      f.cached?.should be_false
    end
  end
end

describe TinySite do
  describe "#body" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar'
      @app.stub! :page => {:layout => 'some_page_layout'}
      @layout_file = StringIO.new('foo')
      File.stub! :open => @layout_file
    end
    it "reads the layout" do
      File.should_receive(:open).with('some_page_layout.haml').and_return(StringIO.new('foo'))
      @app.body
    end
    it "renders the layout" do
      haml_stub = stub(:haml_stub, :render => 'foo')
      Haml::Engine.should_receive(:new).with('foo', :format => :html5).and_return(haml_stub)
      @app.body
    end
    it "uses the view" do
      the_view = stub(:the_view)
      @app.stub! :view => the_view
      haml_stub = stub(:haml_stub)
      Haml::Engine.stub!(:new => haml_stub)
      haml_stub.should_receive(:render).with(the_view)
      @app.body
    end
  end
  describe "#layout" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar'
      @app.instance_variable_set '@request_path', '/foo'
    end
    describe "with layout defined in page" do
      it "returns the page-layout" do
        @app.should_receive(:page).and_return({:layout => 'page_layout'})
        @app.layout.should == 'page_layout'
      end
    end
    describe "with layout defined in global" do
      it "returns the global-layout" do
        @app.stub! :page => {}
        @app.should_receive(:global).and_return({:layout => 'global_layout'})
        @app.layout.should == 'global_layout'
      end
    end
    describe "with layout not defined" do
      it "returns the default layout" do
        @app.stub! :page => {}, :global => {}
        @app.layout.should == 'layout'
      end
    end
  end
  describe "#image_url_for" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar', :image_path => 'imgs'
    end
    it "prepends the image_path" do
      @app.should_receive(:file_url_for).with('beautyful.png', 'imgs').and_return('http://foo/imgs/beautyful.png')
      @app.image_url_for('beautyful.png').should == 'http://foo/imgs/beautyful.png'
    end
  end
  describe "#file_url_for" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar', :file_path_postfix => '?download'
    end
    it "concatenates (more or less) the different path components" do
      @app.file_url_for('my_file').should == 'http://foo/bar/my_file?download'
    end
  end
  describe "#page_content_url_for" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar', :file_extension => 'ext', :file_path_postfix => '?download'
    end
    it "calls #file_url_for with filename and extension" do
      @app.should_receive(:file_url_for).with('some_content_url.ext')
      @app.page_content_url_for('some_content_url')
    end
  end
  describe "#caching_header" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar', :cache_buster => 'bust'
    end
    describe "when the cachebuster is given" do
      before(:each) do
        @app.instance_variable_set '@query_string', 'bust'
      end
      it "doesn't cache" do
        CachedHttpFile.should_receive(:bust).and_return(true)
        @app.caching_header.should == { 'Cache-Control' => 'no-cache' }
      end
    end
    describe "when the cachebuster is not given" do
      before(:each) do
        @app.instance_variable_set '@query_string', 'whatever'
      end
      it "doesn't cache" do
        @app.caching_header.should == { 'Cache-Control' => 'public, max-age=3600' }
      end
    end
  end
  describe "#headers" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar', :cache_buster => 'bust'
    end
    it "adds Content-Type to the caching header" do
      @app.should_receive(:caching_header).and_return({'Cache-Cache' => 'pub'})
      @app.headers.should == {'Cache-Cache' => 'pub'}.merge({'Content-Type' => 'text/html'})
    end
  end
  describe "#call" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar'
      @app.stub :body => 'foo'
      @app.stub :headers => {'some' => 'headers'}
      @app.instance_variable_set '@status', 123
    end
    it "sanitizes paths ending in '/' by a redirect" do
      @app.call('PATH_INFO' => '/foo/bar/').should == [301, {'Location' => '/foo/bar'}, ['']]
    end
    it "returns the set status and the rendered body" do
      @app.call('PATH_INFO' => '/foo').should == [123, {'some' => 'headers'}, ['foo']]
    end
    it "catches errors nicely" do
      error = StandardError.new 'an_error'
      error.stub!(:backtrace => ['one'])
      @app.should_receive(:status).and_raise(error)
      @app.call('PATH_INFO' => '/foo').should == [500, {}, ['Sorry, but something went wrong']]
    end
    it "sets request_path" do
      @app.call('PATH_INFO' => '/foo')
      @app.request_path.should == '/foo'
    end
    it "sets query_string" do
      @app.call('PATH_INFO' => '/foo', 'QUERY_STRING' => 'brabbel')
      @app.query_string.should == 'brabbel'
    end
  end
  describe "#status" do
    before(:each) do
      @app = TinySite.new :file_path => 'http://foo/bar'
    end
    describe "when status is not set alread" do
      it "calls #page to get it" do
        @app.should_receive(:page)
        @app.status
      end
    end
    describe "when status is already set" do
      it "just returns it" do
        @app.instance_variable_set('@status', 123)
        @app.should_receive(:page).never
        @app.status.should == 123
      end
    end
  end
end

describe TinySite::View do
  before(:each) do
    @app = stub(:app)
    @view = TinySite::View.new @app
  end
  describe "delegated methods" do
    it "delegates #request_path to the app" do
      @app.should_receive :request_path
      @view.request_path
    end
    it "delegates #query_string to the app" do
      @app.should_receive :query_string
      @view.query_string
    end
    it "delegates #global to the app" do
      @app.should_receive :global
      @view.global
    end
    it "delegates #page to the app" do
      @app.should_receive :page
      @view.page
    end
    it "delegates #file_url_for to the app" do
      @app.should_receive :file_url_for
      @view.file_url_for
    end
    it "delegates #image_url_for to the app" do
      @app.should_receive :image_url_for
      @view.image_url_for
    end
  end
end
