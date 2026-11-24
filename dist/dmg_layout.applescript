-- Lays out the MailLi DMG window: background picture, big icons,
-- app on the left, Applications on the right, instructions underneath.
on run argv
	set volName to item 1 of argv
	tell application "Finder"
		tell disk volName
			open
			set current view of container window to icon view
			set toolbar visible of container window to false
			set statusbar visible of container window to false
			set the bounds of container window to {200, 120, 840, 622}
			set viewOptions to the icon view options of container window
			set arrangement of viewOptions to not arranged
			set icon size of viewOptions to 112
			set text size of viewOptions to 14
			set background picture of viewOptions to file ".background:background.tiff"
			set position of item "MailLi.app" of container window to {160, 190}
			set position of item "Applications" of container window to {480, 190}
			set position of item "קראו אותי - התקנה.txt" of container window to {320, 385}
			close
			open
			update without registering applications
			delay 2
			close
		end tell
	end tell
end run
