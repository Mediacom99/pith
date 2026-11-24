# The installer's disk image (decision 56), read by dmgbuild from `make package`: Pith and a link to Applications,
# side by side over Support/DMGBackground.png (and its @2x), as Finder will show the window when it opens.
import os.path

application = defines["app"]
name = os.path.basename(application)

format = "UDZO"
files = [application]
symlinks = {"Applications": "/Applications"}
icon = "Support/AppIcon.icns"
background = "Support/DMGBackground.png"

window_rect = ((200, 160), (640, 400))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
arrange_by = None
icon_size = 128
text_size = 13
icon_locations = {name: (160, 176), "Applications": (480, 176)}
