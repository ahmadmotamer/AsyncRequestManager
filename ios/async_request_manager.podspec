Pod::Spec.new do |s|
  s.name             = 'async_request_manager'
  s.version          = '0.3.0'
  s.summary          = 'A Dart utility for managing concurrent async operations.'
  s.description      = <<-DESC
    A lightweight Dart utility for coordinating concurrent asynchronous operations
    with deduplication, cancellation, and parallel-execution strategies.
  DESC
  s.homepage         = 'https://github.com/ahmadmotamer/AsyncRequestManager'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ahmad Motamer' => 'ahmad.mostafa.3939@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '12.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version    = '5.0'
end
