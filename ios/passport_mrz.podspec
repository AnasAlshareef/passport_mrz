Pod::Spec.new do |s|
  s.name             = 'passport_mrz'
  s.version          = '0.1.0'
  s.summary          = 'On-device passport MRZ scanning for Flutter.'
  s.description      = <<-DESC
Native OCR (Vision) plus ICAO 9303 MRZ detection and check-digit validation.
                       DESC
  s.homepage         = 'https://github.com/AnasAlshareef/passport_mrz'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Anas Alshareef' => 'moada7770@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
