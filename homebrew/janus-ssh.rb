cask "janus-ssh" do
  version "0.1.0"
  sha256 "REPLACE_WITH_SHA256"

  url "https://github.com/lshgdut/janus-ssh/releases/download/v#{version}/JanusSSH-#{version}.dmg"
  name "Janus SSH"
  desc "Native macOS SSH Tunnel Manager — visual front-end for ~/.ssh/config"
  homepage "https://github.com/lshgdut/janus-ssh"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "JanusSSH.app"

  zap trash: [
    "~/Library/Application Support/com.lshgdut.janus-ssh",
    "~/Library/Preferences/com.lshgdut.janus-ssh.plist",
    "~/Library/Logs/JanusSSH",
  ]
end