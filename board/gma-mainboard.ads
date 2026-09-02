-- SPDX-License-Identifier: GPL-2.0-or-later

with HW.GFX.GMA;
with HW.GFX.GMA.Display_Probing;

use HW.GFX.GMA;
use HW.GFX.GMA.Display_Probing;

private package GMA.Mainboard is

   -- The 15" non-Retina panel is LVDS, not eDP as on the MacBookPro10,1.
   -- The only external output is the mini-DisplayPort/Thunderbolt jack,
   -- which is routed through the Light Ridge controller; whether it is
   -- usable without bringing that controller up is untested.
   ports : constant Port_List :=
     (LVDS,
      DP1,
      DP2,
      DP3,
      HDMI1,
      HDMI2,
      HDMI3,
      others => Disabled);

end GMA.Mainboard;
