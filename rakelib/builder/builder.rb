# User customizable variables.
# These variables can be set from the command line. Example:
#    $ rake framework_instdir=~/Library/Frameworks sym_instdir=~/bin

$builder_options = {}

def do_option(name, default)
  $builder_options[name] = default
  
  val = ENV[name]
  if val
    if block_given?
      yield val
    else
      val
    end
  else
    default
  end
end

RUBY_INSTALL_NAME = do_option('ruby_install_name', 'macruby')
RUBY_SO_NAME = do_option('ruby_so_name', RUBY_INSTALL_NAME)
ARCHS = 
  if s = ENV['RC_ARCHS']
    $stderr.puts "getting archs from RC_ARCHS!"
    s.strip.split(/\s+/)
  else
    do_option('archs', `arch`.include?('ppc') ? 'ppc' : %w{i386 x86_64}) { |x| x.split(',') }
  end
LLVM_PATH = do_option('llvm_path', '/usr/local')
FRAMEWORK_NAME = do_option('framework_name', 'MacRuby')
FRAMEWORK_INSTDIR = do_option('framework_instdir', '/Library/Frameworks')
SYM_INSTDIR = do_option('sym_instdir', '/usr/local')
NO_WARN_BUILD = !do_option('allow_build_warnings', false)
ENABLE_STATIC_LIBRARY = do_option('enable_static_library', 'no') { 'yes' }
ENABLE_DEBUG_LOGGING = do_option('enable_debug_logging', true) { |x| x == 'true' }
UNEXPORTED_SYMBOLS_LIST = do_option('unexported_symbols_list', nil)
SIMULTANEOUS_JOBS = do_option('jobs', 1) { |x| x.to_i }

# Everything below this comment should *not* be modified.

if ENV['build_as_embeddable']
  $stderr.puts "The 'build_as_embeddable' build configuration has been removed because it is no longer necessary. To package a full version of MacRuby inside your application, please use `macrake deploy` for HotCocoa apps and the `Embed MacRuby` target for Xcode apps."
  exit 1
end

verbose(true)

if `sw_vers -productVersion`.strip < '10.5.6'
  $stderr.puts "Sorry, your environment is not supported. MacRuby requires Mac OS X 10.5.6 or higher." 
  exit 1
end

if `arch`.include?('ppc')
  $stderr.puts "You appear to be using a PowerPC machine. MacRuby's primary architectures are Intel 32-bit and 64-bit (i386 and x86_64). Consequently, PowerPC support may be lacking some features."
end

LLVM_CONFIG = File.join(LLVM_PATH, 'bin/llvm-config')
unless File.exist?(LLVM_CONFIG)
  $stderr.puts "The llvm-config executable was not located as #{LLVM_CONFIG}. Please make sure LLVM is correctly installed on your machine and pass the llvm_config option to rake if necessary."
  exit 1
end

version_h = File.read('version.h')
NEW_RUBY_VERSION = version_h.scan(/#\s*define\s+RUBY_VERSION\s+\"([^"]+)\"/)[0][0]
unless defined?(MACRUBY_VERSION)
  MACRUBY_VERSION = version_h.scan(/#\s*define\s+MACRUBY_VERSION\s+\"(.*)\"/)[0][0]
end

uname_release_number = (ENV['UNAME_RELEASE'] or `uname -r`.scan(/^(\d+)\.\d+\.(\d+)/)[0].join('.'))
NEW_RUBY_PLATFORM = 'universal-darwin' + uname_release_number

FRAMEWORK_PATH = File.join(FRAMEWORK_INSTDIR, FRAMEWORK_NAME + '.framework')
FRAMEWORK_VERSION = File.join(FRAMEWORK_PATH, 'Versions', MACRUBY_VERSION)
FRAMEWORK_USR = File.join(FRAMEWORK_VERSION, 'usr')
FRAMEWORK_USR_LIB = File.join(FRAMEWORK_USR, 'lib')
FRAMEWORK_USR_LIB_RUBY = File.join(FRAMEWORK_USR_LIB, 'ruby')

RUBY_LIB = File.join(FRAMEWORK_USR_LIB_RUBY, NEW_RUBY_VERSION)
RUBY_ARCHLIB = File.join(RUBY_LIB, NEW_RUBY_PLATFORM)
RUBY_SITE_LIB = File.join(FRAMEWORK_USR_LIB_RUBY, 'site_ruby')
RUBY_SITE_LIB2 = File.join(RUBY_SITE_LIB, NEW_RUBY_VERSION)
RUBY_SITE_ARCHLIB = File.join(RUBY_SITE_LIB2, NEW_RUBY_PLATFORM)
RUBY_VENDOR_LIB = File.join(FRAMEWORK_USR_LIB_RUBY, 'vendor_ruby')
RUBY_VENDOR_LIB2 = File.join(RUBY_VENDOR_LIB, NEW_RUBY_VERSION)
RUBY_VENDOR_ARCHLIB = File.join(RUBY_VENDOR_LIB2, NEW_RUBY_PLATFORM)

INSTALL_NAME = File.join(FRAMEWORK_USR_LIB, 'lib' + RUBY_SO_NAME + '.dylib')
ARCHFLAGS = ARCHS.map { |a| '-arch ' + a }.join(' ')
LLVM_MODULES = "core jit nativecodegen bitwriter"

CC = '/usr/bin/gcc'
CXX = '/usr/bin/g++'
CFLAGS = "-I. -I./include -I./onig -I/usr/include/libxml2 #{ARCHFLAGS} -fno-common -pipe -O3 -g -Wall -fexceptions"
CFLAGS << " -Wno-parentheses -Wno-deprecated-declarations -Werror" if NO_WARN_BUILD
OBJC_CFLAGS = CFLAGS + " -fobjc-gc-only"
CXXFLAGS = `#{LLVM_CONFIG} --cxxflags #{LLVM_MODULES}`.sub(/-DNDEBUG/, '').strip
CXXFLAGS << " -I. -I./include -g -Wall #{ARCHFLAGS}"
CXXFLAGS << " -Wno-parentheses -Wno-deprecated-declarations -Werror" if NO_WARN_BUILD
CXXFLAGS << " -DLLVM_TOT" if ENV['LLVM_TOT']
LDFLAGS = `#{LLVM_CONFIG} --ldflags --libs #{LLVM_MODULES}`.strip.gsub(/\n/, '')
LDFLAGS << " -lpthread -ldl -lxml2 -lobjc -lauto -framework Foundation"
DLDFLAGS = "-dynamiclib -undefined suppress -flat_namespace -install_name #{INSTALL_NAME} -current_version #{MACRUBY_VERSION} -compatibility_version #{MACRUBY_VERSION}"
DLDFLAGS << " -unexported_symbols_list #{UNEXPORTED_SYMBOLS_LIST}" if UNEXPORTED_SYMBOLS_LIST
CFLAGS << " -std=c99" # we add this one later to not conflict with C++ flags
OBJC_CFLAGS << " -std=c99"

OBJS = %w{ 
  array bignum class compar complex enum enumerator error eval file load proc 
  gc hash inits io math numeric object pack parse prec dir process
  random range rational re onig/regcomp onig/regext onig/regposix onig/regenc
  onig/reggnu onig/regsyntax onig/regerror onig/regparse onig/regtrav
  onig/regexec onig/regposerr onig/regversion onig/enc/ascii onig/enc/unicode
  onig/enc/utf8 onig/enc/euc_jp onig/enc/sjis onig/enc/iso8859_1
  onig/enc/utf16_be onig/enc/utf16_le onig/enc/utf32_be onig/enc/utf32_le
  ruby signal sprintf st string struct time transcode util variable version
  thread id objc bs encoding main dln dmyext marshal gcd
  vm_eval prelude miniprelude gc-stub bridgesupport compiler dispatcher vm
  debugger MacRuby MacRubyDebuggerConnector NSDictionary
}

OBJS_CFLAGS = {
  # Make sure everything gets inlined properly + compile as Objective-C++.
  'dispatcher' => '--param inline-unit-growth=10000 --param large-function-growth=10000 -x objective-c++'
}

class Builder
  # Runs the given array of +commands+ in parallel. The amount of spawned
  # simultaneous jobs is determined by the `jobs' env variable. The default
  # value is 1.
  #
  # When the members of the +commands+ array are in turn arrays of strings,
  # then those commands will be executed in consecutive order.
  def self.parallel_execute(commands)
    commands = commands.dup

    Array.new(SIMULTANEOUS_JOBS) do |i|
      Thread.new do
        while c = commands.shift
          Array(c).each { |command| sh(command) }
        end
      end
    end.each { |t| t.join }
  end

  attr_reader :objs, :cflags, :cxxflags
  attr_accessor :objc_cflags, :ldflags, :dldflags

  def initialize(objs)
    @objs = objs.dup
    @cflags = CFLAGS
    @cxxflags = CXXFLAGS
    @objc_cflags = OBJC_CFLAGS
    @ldflags = LDFLAGS
    @dldflags = DLDFLAGS
    @objs_cflags = OBJS_CFLAGS
    @obj_sources = {}
    @header_paths = {}
  end

  def build(objs=nil)
    objs ||= @objs
    objs.each do |obj| 
      if should_build?(obj) 
        s = obj_source(obj)
        cc, flags = 
          case File.extname(s)
            when '.c' then [CC, @cflags]
            when '.cpp' then [CXX, @cxxflags]
            when '.m' then [CC, @objc_cflags]
            when '.mm' then [CXX, @cxxflags + ' ' + @objc_cflags]
          end
        if f = @objs_cflags[obj]
          flags += " #{f}"
        end
        sh("#{cc} #{flags} -c #{s} -o #{obj}.o")
      end
    end
  end
 
  def link_executable(name, objs=nil, ldflags=nil)
    link(objs, ldflags, "-o #{name}", name)
  end

  def link_dylib(name, objs=nil, ldflags=nil)
    link(objs, ldflags, "#{@dldflags} -o #{name}", name)
  end

  def link_archive(name, objs=nil)
    objs ||= @objs
    if should_link?(name, objs)
      rm_f(name)
      sh("/usr/bin/ar rcu #{name} #{objs.map { |x| x + '.o' }.join(' ') }")
      sh("/usr/bin/ranlib #{name}")
    end
  end

  def clean
    @objs.map { |o| o + '.o' }.select { |o| File.exist?(o) }.each { |o| rm_f(o) }
  end
 
  private

  def link(objs, ldflags, args, name)
    objs ||= @objs
    ldflags ||= @ldflags
    if should_link?(name, objs)
      sh("#{CXX} #{@cflags} #{objs.map { |x| x + '.o' }.join(' ') } #{ldflags} #{args}")
    end
  end

  def should_build?(obj)
    if File.exist?(obj + '.o')
      src_time = File.mtime(obj_source(obj))
      obj_time = File.mtime(obj + '.o')
      src_time > obj_time \
        or dependencies[obj].any? { |f| File.mtime(f) > obj_time }
    else
      true
    end
  end

  def should_link?(bin, objs)
    if File.exist?(bin)
      mtime = File.mtime(bin)
      objs.any? { |o| File.mtime(o + '.o') > mtime }
    else
      true
    end
  end

  def err(*args)
    $stderr.puts args
    exit 1
  end

  def obj_source(obj)
    s = @obj_sources[obj]
    unless s
      s = ['.c', '.cpp', '.m', '.mm'].map { |e| obj + e }.find { |p| File.exist?(p) }
      err "cannot locate source file for object `#{obj}'" if s.nil?
      @obj_sources[obj] = s
    end
    s
  end

  HEADER_DIRS = %w{. include include/ruby}
  def header_path(hdr)
    p = @header_paths[hdr]
    unless p
      p = HEADER_DIRS.map { |d| File.join(d, hdr) }.find { |p| File.exist?(p) }
      @header_paths[hdr] = p
    end
    p
  end
  
  def locate_headers(cont, src)
    txt = File.read(src)
    txt.scan(/#include\s+\"([^"]+)\"/).flatten.each do |header|
      p = header_path(header)
      if p and !cont.include?(p)
        cont << p
        locate_headers(cont, p)
      end
    end
  end
  
  def dependencies
    unless @obj_dependencies
      @obj_dependencies = {}
      @objs.each do |obj| 
        ary = []
        locate_headers(ary, obj_source(obj))
        @obj_dependencies[obj] = ary.uniq
      end
    end
    @obj_dependencies
  end
  
  class Ext
    EXTENSIONS = ['ripper', 'digest', 'etc', 'readline', 'libyaml', 'fcntl', 'socket', 'zlib', 'bigdecimal', 'openssl', 'json'].sort
    
    def self.extension_dirs
      EXTENSIONS.map do |name|
        Dir.glob(File.join('ext', name, '**/extconf.rb'))
      end.flatten.map { |f| File.dirname(f) }
    end
    
    def self.build
      commands = extension_dirs.map { |dir| new(dir).build_commands }
      Builder.parallel_execute(commands)
    end
    
    def self.install
      extension_dirs.each do |dir|
        sh new(dir).install_command
      end
    end
    
    def self.clean
      extension_dirs.each do |dir|
        new(dir).clean_commands.each { |cmd| sh(cmd) }
      end
    end
    
    attr_reader :dir
    
    def initialize(dir)
      @dir = dir
    end
    
    def srcdir
      @srcdir ||= File.join(dir.split(File::SEPARATOR).map { |x| '..' })
    end
    
    def makefile
      @makefile ||= File.join(@dir, 'Makefile')
    end
    
    def extconf
      File.join(@dir, 'extconf.rb')
    end
    
    def create_makefile_command
      if !File.exist?(makefile) or File.mtime(extconf) > File.mtime(makefile)
        "cd #{dir} && #{srcdir}/miniruby -I#{srcdir} -I#{srcdir}/lib -r rbconfig -e \"RbConfig::CONFIG['libdir'] = '#{srcdir}'; require './extconf.rb'\""
      end
    end
    
    def build_commands
      [create_makefile_command, make_command(:all)].compact
    end
    
    def clean_commands
      return [] unless File.exist?(makefile)
      [create_makefile_command, make_command(:clean), "rm -f #{makefile}"].compact
    end
    
    def install_command
      make_command(:install)
    end
    
    private
    
    # Possible targets are:
    # * all
    # * install
    # * clean
    def make_command(target)
      cmd = "cd #{dir} && /usr/bin/make top_srcdir=#{srcdir} ruby=\"#{srcdir}/miniruby -I#{srcdir} -I#{srcdir}/lib\" extout=#{srcdir}/.ext hdrdir=#{srcdir}/include arch_hdrdir=#{srcdir}/include"
      cmd << (target == :all ? " libdir=#{srcdir}" : " #{target}")
      cmd
    end
  end
end

$builder = Builder.new(OBJS)