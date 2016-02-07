Pod::Spec.new do |s|

  # ―――  Spec Metadata  ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――― #
  #
  #  These will help people to find your library, and whilst it
  #  can feel like a chore to fill in it's definitely to your advantage. The
  #  summary should be tweet-length, and the description more in depth.
  #

  s.name         = "Elixir"
  s.version      = "0.1.2"
  s.summary      = "Elixir is a simple and lightweight object persistence solution."

  s.description  = " Elixir is a simple (only 4 core APIs) and lightweight (only 2 files, around 2000 lines of code) persistent solution. It fully utilizes Objective-C's runtime environment to automatically save and load object properties to and from a sqlite database with minimum user interaction; it provides object query support with the NSPredicate interface, and most importantly, with simplicity as the main design objective, Elixir is very easy to use. Elixir is perfect for the projects that are too complex to use NSUserDefault, but not complicated enough to require the convolution of CoreData or raw SQL."

  s.homepage     = "https://github.com/iCharlesHu/Elixir"
  s.license      = "MIT"
  s.author             = 'Yizhe Hu'

  #  Objective-C Runtime is available in OS X 10.5+ and iOS 2.0+
  s.ios.deployment_target = "5.0"
  s.osx.deployment_target = "10.7"

  s.source       = { :git => "https://github.com/iCharlesHu/Elixir.git",
                     :tag => s.version }
  s.source_files  = "Source/*.{h,m}"

  s.requires_arc = true

  s.library   = "sqlite3"
end
