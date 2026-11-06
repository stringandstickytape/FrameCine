extends RefCounted

## The menu button's press and hold (docs/ui-design.md). A small state machine, no nodes, so tests/test_pane.gd can
## drive it with made-up button timings. Where the menu shows is the tablet's (ui/tablet.gd pose(); the user,
## 2026-11-06: the front panel, which had its own place and head follow here, is gone).
##
## The menu button: a short press toggles the panel; held RECENTRE_HOLD seconds while it is open, it recentres the panel
## in front of the head instead (MenuPress below). All numbers are to be tuned in the headset.

## Seconds the menu button is held to recentre ([pane] recentre_hold).
const RECENTRE_HOLD := 0.6


## The menu button's press, hold and release. press() answers what to do at once: "open" (the panel was closed: it
## opens in front of the head, which is the recentre too), "cancel" (another use took the press, such as seat picking)
## or "" (it was open: wait). step() answers "recentre" once when the button has been held `hold` seconds; release()
## answers "close" for a short press on an open panel, else "".
class MenuPress:
	extends RefCounted

	var hold := RECENTRE_HOLD
	var held := -1.0
	var hand: Object
	var _waiting := false

	func press(p_hand: Object, open: bool, cancel := false) -> String:
		hand = p_hand
		held = 0.0
		_waiting = open and not cancel
		if cancel:
			return "cancel"
		return "" if open else "open"

	func step(delta: float) -> String:
		if held < 0.0:
			return ""
		held += delta
		if _waiting and held >= hold:
			_waiting = false
			return "recentre"
		return ""

	func release(p_hand: Object) -> String:
		if held < 0.0 or p_hand != hand:
			return ""
		held = -1.0
		if _waiting:
			_waiting = false
			return "close"
		return ""

	func is_held() -> bool:
		return held >= 0.0
