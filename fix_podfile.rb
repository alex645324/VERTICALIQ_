podfile_path = 'ios/Podfile'
content = File.read(podfile_path)

# Replace the post_install section
new_post_install = <<~RUBY
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    
    # Fix for BoringSSL-GRPC compilation error
    if target.name == 'BoringSSL-GRPC'
      target.source_build_phase.files.each do |file|
        if file.settings && file.settings['COMPILER_FLAGS']
          flags = file.settings['COMPILER_FLAGS'].split
          flags.reject! { |flag| flag == '-GCC_WARN_INHIBIT_ALL_WARNINGS' }
          file.settings['COMPILER_FLAGS'] = flags.join(' ')
        end
      end
    end
    
    # Ensure iOS 12.0 deployment target
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '12.0'
    end
  end
end
RUBY

# Replace existing post_install section
content = content.gsub(/post_install do \|installer\|.*?^end$/m, new_post_install.strip)

File.write(podfile_path, content)
puts "Podfile updated successfully!"
