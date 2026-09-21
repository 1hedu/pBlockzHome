# Decimal.gd: money maths as pure functions on decimal strings, no world or chain. Every
# number here is past what a double holds exactly -- 2^53 is about 9.0e15 and one PLS is 1e18
# wei -- so a float answer is nearly right: unspendable dust in a balance, a revert in a swap.
#
#   godot --path . -s res://tests/decimal_test.gd
extends SceneTree

const Decimal = preload("res://host/Decimal.gd")

var passed := 0
var failed := 0

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func eq(got: String, want: String, what: String) -> void:
	check(got == want, "%s  (%s)" % [what, got if got == want else "%s, wanted %s" % [got, want]])

func _initialize() -> void:
	print("decimal maths")

	check(Decimal.less_than("9", "10"), "9 < 10, by length rather than by spelling")
	check(not Decimal.less_than("10", "9"), "and 10 is not less than 9")
	check(Decimal.less_than("0999999999999999999", "1000000000000000000"),
		"a leading zero does not make a number bigger")
	check(not Decimal.less_than("1000000000000000000", "1000000000000000000"),
		"and nothing is less than itself")

	eq(Decimal.add("999", "1"), "1000", "carrying all the way")
	eq(Decimal.add("1000000000000000000", "1000000000000000000"), "2000000000000000000",
		"two PLS is two PLS, exactly")
	eq(Decimal.subtract("1000000000000000000", "1"), "999999999999999999",
		"a PLS less a wei keeps every digit -- a float loses the last three")
	eq(Decimal.add("0", "0"), "0", "nothing and nothing")

	eq(Decimal.mul("12345678901234567890", "1000000000000000000"),
		"12345678901234567890000000000000000000", "twenty digits by eighteen zeroes")
	eq(Decimal.mul_small("123456789012345678", 7), "864197523086419746", "by a small int")
	eq(Decimal.mul("0", "999999999999999999999"), "0", "anything by nothing")
	eq(Decimal.mul("1", "1"), "1", "one by one")

	eq(Decimal.div("1000000000000000000", "3"), "333333333333333333", "a third of a PLS, floored")
	eq(Decimal.div("7", "8"), "0", "and a fraction floors to nothing rather than rounding")
	eq(Decimal.div("100", "0"), "0", "dividing by nothing is nothing, not a crash")
	eq(Decimal.mul_div("1000000000000000000", "997", "1000"), "997000000000000000",
		"a 0.3% fee taken the way a router takes it")

	check(Decimal.ratio_bps("1", "2") == 5000, "half is 5000 bps")
	check(Decimal.ratio_bps("1", "1") == 10000, "all of it is 10000")
	check(Decimal.ratio_bps("3", "1") == 10000, "and more than all of it is capped there")
	check(Decimal.ratio_bps("1", "1000000000000000000") == 0, "a wei of a PLS rounds to nothing")

	eq(Decimal.from_hex("0x0"), "0", "zero")
	eq(Decimal.from_hex("0xde0b6b3a7640000"), "1000000000000000000", "one PLS, off the chain")
	eq(Decimal.from_hex("0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
		"115792089237316195423570985008687907853269984665640564039457584007913129639935",
		"and a full uint256, which is the case a 64-bit int cannot even hold")

	eq(Decimal.to_units("1", 18), "1000000000000000000", "one whole token")
	eq(Decimal.to_units("1.5", 18), "1500000000000000000", "and a half of one")
	eq(Decimal.to_units("0.000000000000000001", 18), "1", "down to a single wei")
	eq(Decimal.to_units("1.23456789", 8), "123456789", "an 8-decimal token, exactly")
	eq(Decimal.to_units("1.9999999999999999999", 18), "1999999999999999999",
		"more places than the token has are cut, not rounded up into a wei nobody owns")

	eq(Decimal.format("1000000000000000000", 18, 2), "1", "one PLS reads as one")
	eq(Decimal.format("1500000000000000000", 18, 2), "1.5", "and a half reads as a half")
	eq(Decimal.format("1", 18, 2), "0", "a single wei is not 0.01 of anything")
	eq(Decimal.format("123456789012345678901", 18, 2), "123.45",
		"a hundred-odd PLS, cut at two places rather than rounded")

	# What a person types -> what the chain wants -> back: the path a swap takes, and the one
	# place an error is spendable.
	for amount in ["1", "0.5", "1234.5678", "0.000000000000000001", "999999999"]:
		var units := Decimal.to_units(amount, 18)
		var back := Decimal.format(units, 18, 18)
		check(back.to_float() == amount.to_float(),
			"%s -> %s -> %s survives the round trip" % [amount, units, back])

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
