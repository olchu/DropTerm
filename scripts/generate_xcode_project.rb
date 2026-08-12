#!/usr/bin/env ruby

require "xcodeproj"

root = File.expand_path("..", __dir__)
project_path = File.join(root, "DropTerm.xcodeproj")
project = Xcodeproj::Project.new(project_path)

sources_group = project.main_group.new_group("DropTerm", "Sources/DropTerm")
tests_group = project.main_group.new_group("DropTermTests", "Tests/DropTermTests")
app_target = project.new_target(:application, "DropTerm", :osx, "15.0")
test_target = project.new_target(:unit_test_bundle, "DropTermTests", :osx, "15.0")
test_target.add_dependency(app_target)

Dir.glob(File.join(root, "Sources/DropTerm/*.swift")).sort.each do |path|
  app_target.source_build_phase.add_file_reference(sources_group.new_file(path))
end

Dir.glob(File.join(root, "Tests/DropTermTests/*.swift")).sort.each do |path|
  test_target.source_build_phase.add_file_reference(tests_group.new_file(path))
end

swift_term = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
swift_term.repositoryURL = "https://github.com/migueldeicaza/SwiftTerm.git"
swift_term.requirement = {
  "kind" => "upToNextMajorVersion",
  "minimumVersion" => "1.15.0"
}
project.root_object.package_references << swift_term

swift_term_product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
swift_term_product.package = swift_term
swift_term_product.product_name = "SwiftTerm"
app_target.package_product_dependencies << swift_term_product

swift_term_build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
swift_term_build_file.product_ref = swift_term_product
app_target.frameworks_build_phase.files << swift_term_build_file

app_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.olchu.DropTerm"
  settings["PRODUCT_NAME"] = "DropTerm"
  settings["DEVELOPMENT_TEAM"] = "6PEVX4KK6Z"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["SWIFT_VERSION"] = "6.0"
  settings["MACOSX_DEPLOYMENT_TARGET"] = "15.0"
  settings["GENERATE_INFOPLIST_FILE"] = "YES"
  settings["INFOPLIST_KEY_CFBundleDisplayName"] = "DropTerm"
  settings["INFOPLIST_KEY_LSApplicationCategoryType"] = "public.app-category.utilities"
  settings["INFOPLIST_KEY_LSUIElement"] = "YES"
  settings["INFOPLIST_KEY_NSDocumentsFolderUsageDescription"] = "DropTerm needs access so your shell can work with files in Documents."
  # A local terminal must launch the user's shell without App Sandbox restrictions.
  settings["ENABLE_APP_SANDBOX"] = "NO"
  settings["ENABLE_HARDENED_RUNTIME"] = configuration.name == "Release" ? "YES" : "NO"
end

test_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.olchu.DropTermTests"
  settings["DEVELOPMENT_TEAM"] = "6PEVX4KK6Z"
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["SWIFT_VERSION"] = "6.0"
  settings["MACOSX_DEPLOYMENT_TARGET"] = "15.0"
  settings["GENERATE_INFOPLIST_FILE"] = "YES"
  settings["TEST_HOST"] = "$(BUILT_PRODUCTS_DIR)/DropTerm.app/Contents/MacOS/DropTerm"
  settings["BUNDLE_LOADER"] = "$(TEST_HOST)"
end

project.save
puts "Generated #{project_path}"
