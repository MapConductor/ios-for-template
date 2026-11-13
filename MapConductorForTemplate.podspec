Pod::Spec.new do |s|
  s.name = "MapConductorForTemplate"
  s.version = "1.4.0"
  s.summary = "MapConductor's driver template (not a real map provider)."
  # 他のプロバイダは LICENSE ファイルを持つが、この雛形は単体で配布しないので、テキストを直接置く。
  s.license = { :type => "Apache-2.0", :text => "Copyright MapConductor. Licensed under the Apache License, Version 2.0." }
  s.author = "MapConductor"
  s.homepage = "https://github.com/MapConductor/ios-for-template"
  s.source = { :git => "https://github.com/MapConductor/ios-for-template.git", :tag => s.version.to_s }
  s.platform = :ios, "15.1"
  s.swift_version = "5.9"
  s.source_files = "Sources/MapConductorForTemplate/**/*.swift"
  s.dependency "MapConductorCore", "~> 1.4"
  # 本物のドライバーはここに地図SDKの依存を足す（`s.dependency "MapLibre", "~> 7.0"` 等）。
  # 雛形の地図は描画面を持たない代役なので、ベンダ依存は無い。
end
