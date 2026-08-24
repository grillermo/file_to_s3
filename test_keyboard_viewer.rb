html = File.read(File.join(__dir__, "files", "keyboard-in-action-viewer.html"))

%w[control option command shift alt-lock].each do |modifier|
  raise "Missing #{modifier} modifier" unless html.include?(%(data-modifier="#{modifier}"))
end

%w[id="keyboard" id="live-key" function\ render].each do |marker|
  raise "Missing viewer marker #{marker}" unless html.include?(marker)
end

raise "Alt Lock must participate in Option state" unless html.include?("option || modifiers.altLock")
raise "Missing external-keyboard capture" unless html.include?('addEventListener("keydown"')

puts "Keyboard viewer structural check passed"
