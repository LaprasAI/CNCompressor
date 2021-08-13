Pod::Spec.new do |s|

# 1
s.platform = :ios
s.ios.deployment_target = '11.0'
s.name = "CNCompressor"
s.summary = "summary"
s.requires_arc = true

# 2
s.version = "0.1.0"

# 3
s.license = { :type => "MIT", :file => "LICENSE" }

# 4 - Replace with your name and e-mail address
s.author = { "liyuyang" => "liyuyang@corp.netease.com" }

# 5 - Replace this URL with your own GitHub page's URL (from the address bar)
s.homepage = "https://www.google.com"

# 6 - Replace this URL with your own Git URL from "Quick Setup"
s.source = { :git => "https://github.com/LaprasAI/CNCompressor.git",
             :tag => "#{s.version}" }

# 7
s.framework = "AVFoundation"

# 8
s.source_files = "*.{swift}"

# 9
#s.resources = "CNCompressor/**/*.{png,jpeg,jpg,storyboard,xib,xcassets}"

# 10
s.swift_version = "5.0"

end
