cask "sushi-buddy" do
  version :latest
  sha256 :no_check

  url "https://github.com/NikolajMosbaek/sushi-buddy/releases/latest/download/Sushi-Buddy-macOS-arm64.zip"
  name "Sushi Buddy"
  desc "Propeller-hat sushi that flies across the screen to cheer you on"
  homepage "https://github.com/NikolajMosbaek/sushi-buddy"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Sushi Buddy.app"

  uninstall quit: "com.nsscode.SushiBuddy"

  zap trash: [
    "~/Library/Application Support/Sushi Buddy",
    "~/Library/Preferences/com.nsscode.SushiBuddy.plist",
  ]
end
