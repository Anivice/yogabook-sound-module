#!/usr/bin/env python3
"""Prepare the Yoga Book YB1-X91F audio OOT backport tree.

This file intentionally does not vendor the upstream Linux machine driver.
The build workflow retrieves the reviewed patch with b4 and extracts the new
source file from that mailbox, then applies the Yoga Book-specific adaptations.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys


ASOC_DRIVER_PATH = "sound/soc/intel/boards/cht_rt5677.c"


def extract_new_file_from_patch(patch_text: str, target_path: str) -> str:
    """Extract a newly-created file from a unified git patch/mailbox."""
    marker = f"diff --git a/{target_path} b/{target_path}"
    start = patch_text.find(marker)
    if start < 0:
        raise ValueError(f"patch does not contain {target_path}")

    section = patch_text[start:]
    next_diff = section.find("\ndiff --git ", len(marker))
    if next_diff >= 0:
        section = section[:next_diff]

    if f"+++ b/{target_path}" not in section or "new file mode" not in section:
        raise ValueError(f"{target_path} is not a new-file patch")

    lines = section.splitlines()
    in_hunk = False
    output: list[str] = []
    for line in lines:
        if line.startswith("@@ "):
            in_hunk = True
            continue
        if not in_hunk:
            continue
        if line == "-- ":
            break
        if line.startswith("+") and not line.startswith("+++"):
            output.append(line[1:])
        elif line.startswith("\\ No newline at end of file"):
            continue
        elif line.startswith("diff --git "):
            break
        elif line and line[0] in " -":
            # A new-file patch should only carry '+' lines in its hunks.  If
            # b4 ever gives us something else, fail rather than silently emit
            # a corrupted source file.
            raise ValueError(f"unexpected non-addition line in {target_path} hunk: {line!r}")

    if not output:
        raise ValueError(f"no added lines found for {target_path}")
    return "\n".join(output) + "\n"


def patch_cherrytrail_match(source: str) -> str:
    """Add the YB1-X91F/L 10EC5677 machine-table entry."""
    if '"10EC5677"' in source and '"cht-rt5677"' in source:
        return source

    anchor = re.search(
        r"(?m)^(?P<indent>[ \t]*)\{\n(?P=indent)[ \t]+\.comp_ids = &rt5645_comp_ids,",
        source,
    )
    if not anchor:
        raise ValueError("could not find the Cherry Trail rt5645 table anchor")

    indent = anchor.group("indent")
    body = indent + "\t"
    entry = (
        f'{indent}{{\n'
        f'{body}/* Lenovo Yoga Book YB1-X91F/L */\n'
        f'{body}.id = "10EC5677",\n'
        f'{body}.drv_name = "cht-rt5677",\n'
        f'{body}.fw_filename = "intel/fw_sst_22a8.bin",\n'
        f'{body}.board = "cht_rt5677",\n'
        f'{body}.sof_tplg_filename = "sof-cht-rt5677.tplg",\n'
        f'{indent}}},\n'
    )
    return source[: anchor.start()] + entry + source[anchor.start() :]


_AUDIO_DECLS = r'''
/* Yoga Book X91F/L audio resources missing from the firmware description. */
static const struct software_node lenovo_yb1_x91_rt5677_node;

static const struct property_entry lenovo_yb1_x91_rt5677_props[] = {
	/* GPIO2 drives the second speaker amp; GPIO4 drives headphones. */
	PROPERTY_ENTRY_GPIO("speaker-enable2-gpios",
			    &lenovo_yb1_x91_rt5677_node, 2, GPIO_ACTIVE_HIGH),
	PROPERTY_ENTRY_GPIO("headphone-enable-gpios",
			    &lenovo_yb1_x91_rt5677_node, 4, GPIO_ACTIVE_HIGH),
	{ }
};

static const struct software_node lenovo_yb1_x91_rt5677_node = {
	.name = "rt5677",
	.properties = lenovo_yb1_x91_rt5677_props,
};

static const struct property_entry lenovo_yb1_x91_ts3a227e_props[] = {
	/* Value taken from the Lenovo Android kernel code drop. */
	PROPERTY_ENTRY_U32("ti,micbias", 7),
	{ }
};

static const struct software_node lenovo_yb1_x91_ts3a227e_node = {
	.properties = lenovo_yb1_x91_ts3a227e_props,
};

static const struct software_node *lenovo_yb1_x91_audio_swnodes[] = {
	&lenovo_yb1_x91_rt5677_node,
	NULL
};

'''

_TS3A_CLIENT = r'''
	{
		/* The jack-detection IC is described as a secondary RT5677 resource. */
		.board_info = {
			.type = "ts3a227e",
			.addr = 0x3b,
			.dev_name = "ts3a227e",
			.swnode = &lenovo_yb1_x91_ts3a227e_node,
		},
		.adapter_path = "\\_SB_.PCI0.I2C1",
		.irq_data = {
			.type = X86_ACPI_IRQ_TYPE_GPIOINT,
			.chip = "INT33FF:00",
			.index = 77,
			.trigger = ACPI_EDGE_SENSITIVE,
			.polarity = ACPI_ACTIVE_LOW,
			.con_id = "ts3a227e_irq",
		},
	},
'''

_X91_AUDIO_HELPERS = r'''
#define YB1_X91_RT5677_DEVICE "i2c-10EC5677:00"
static struct device *lenovo_yb1_x91_rt5677_dev;

static int __init lenovo_yb1_x91_audio_init(struct device *dev)
{
	struct device *codec_dev;
	int ret;

	codec_dev = bus_find_device_by_name(&i2c_bus_type, NULL,
					    YB1_X91_RT5677_DEVICE);
	if (!codec_dev) {
		dev_warn(dev, "cannot find %s, audio will be unavailable\n",
			 YB1_X91_RT5677_DEVICE);
		return 0;
	}

	ret = device_add_software_node(codec_dev, &lenovo_yb1_x91_rt5677_node);
	if (ret) {
		dev_warn(dev, "failed to add audio properties to %s: %d\n",
			 YB1_X91_RT5677_DEVICE, ret);
		put_device(codec_dev);
		return 0;
	}

	/* Ensure the codec GPIO provider is initialized with the new fwnode. */
	ret = device_reprobe(codec_dev);
	if (ret)
		dev_warn(dev, "failed to reprobe %s: %d\n",
			 YB1_X91_RT5677_DEVICE, ret);

	lenovo_yb1_x91_rt5677_dev = codec_dev;
	return 0;
}

static void lenovo_yb1_x91_audio_exit(void)
{
	if (!lenovo_yb1_x91_rt5677_dev)
		return;

	device_remove_software_node(lenovo_yb1_x91_rt5677_dev);
	put_device(lenovo_yb1_x91_rt5677_dev);
	lenovo_yb1_x91_rt5677_dev = NULL;
}

'''

_X91_INFO = r'''const struct x86_dev_info lenovo_yogabook_x91_info __initconst = {
	.swnode_group = lenovo_yb1_x91_audio_swnodes,
	.i2c_client_info = lenovo_yogabook_x91_i2c_clients,
	.i2c_client_count = ARRAY_SIZE(lenovo_yogabook_x91_i2c_clients),
	.gpiochip_type = X86_GPIOCHIP_CHERRYVIEW,
	.init = lenovo_yb1_x91_audio_init,
	.exit = lenovo_yb1_x91_audio_exit,
};'''


def _find_initializer_span(source: str, declaration: str) -> tuple[int, int, int, int]:
    """Return (declaration_start, open_brace, close_brace, end_after_semicolon).

    The scanner intentionally keys on the C symbol instead of surrounding
    comments/whitespace.  It skips comments and quoted strings while balancing
    braces so harmless formatting changes cannot break the backport.
    """
    start = source.find(declaration)
    if start < 0:
        raise ValueError(f"could not find declaration: {declaration}")

    eq = source.find("=", start + len(declaration))
    if eq < 0:
        raise ValueError(f"could not find initializer for: {declaration}")
    open_brace = source.find("{", eq)
    if open_brace < 0:
        raise ValueError(f"could not find opening brace for: {declaration}")

    depth = 0
    state = "code"
    i = open_brace
    while i < len(source):
        ch = source[i]
        nxt = source[i + 1] if i + 1 < len(source) else ""

        if state == "code":
            if ch == "/" and nxt == "*":
                state = "block_comment"
                i += 2
                continue
            if ch == "/" and nxt == "/":
                state = "line_comment"
                i += 2
                continue
            if ch == '"':
                state = "string"
                i += 1
                continue
            if ch == "'":
                state = "char"
                i += 1
                continue
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    close_brace = i
                    j = close_brace + 1
                    while j < len(source) and source[j].isspace():
                        j += 1
                    if j >= len(source) or source[j] != ";":
                        raise ValueError(f"initializer is not terminated by ';': {declaration}")
                    return start, open_brace, close_brace, j + 1
        elif state == "block_comment":
            if ch == "*" and nxt == "/":
                state = "code"
                i += 2
                continue
        elif state == "line_comment":
            if ch == "\n":
                state = "code"
        elif state in ("string", "char"):
            quote = '"' if state == "string" else "'"
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                state = "code"

        i += 1

    raise ValueError(f"unterminated initializer: {declaration}")


def patch_lenovo_audio(source: str) -> str:
    """Backport only the v3 Yoga Book audio board resources."""
    if "lenovo_yb1_x91_audio_init" in source:
        return source

    decl_anchor = "static const struct x86_i2c_client_info lenovo_yb1_x90_i2c_clients[] __initconst = {"
    pos = source.find(decl_anchor)
    if pos < 0:
        raise ValueError("could not find Yoga Book X90 I2C declaration anchor")
    source = source[:pos] + _AUDIO_DECLS + source[pos:]

    clients_decl = "static const struct x86_i2c_client_info lenovo_yogabook_x91_i2c_clients[] __initconst"
    _, _, clients_close, _ = _find_initializer_span(source, clients_decl)
    source = source[:clients_close] + _TS3A_CLIENT + source[clients_close:]

    info_decl = "const struct x86_dev_info lenovo_yogabook_x91_info __initconst"
    info_start, _, _, info_end = _find_initializer_span(source, info_decl)
    source = source[:info_start] + _X91_AUDIO_HELPERS + _X91_INFO + source[info_end:]
    return source


def _read(path: pathlib.Path) -> str:
    return path.read_text(encoding="utf-8")


def _write(path: pathlib.Path, data: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding="utf-8")


def cmd_extract_driver(args: argparse.Namespace) -> None:
    mailbox = _read(pathlib.Path(args.mailbox))
    driver = extract_new_file_from_patch(mailbox, ASOC_DRIVER_PATH)
    _write(pathlib.Path(args.output), driver)


def cmd_patch_tree(args: argparse.Namespace) -> None:
    root = pathlib.Path(args.tree)
    match = root / "sound/soc/intel/common/soc-acpi-intel-cht-match.c"
    lenovo = root / "drivers/platform/x86/x86-android-tablets/lenovo.c"
    _write(match, patch_cherrytrail_match(_read(match)))
    _write(lenovo, patch_lenovo_audio(_read(lenovo)))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("extract-driver", help="extract cht_rt5677.c from a b4 mailbox")
    p.add_argument("--mailbox", required=True)
    p.add_argument("--output", required=True)
    p.set_defaults(func=cmd_extract_driver)

    p = sub.add_parser("patch-tree", help="apply the X91F match/audio-resource backport")
    p.add_argument("--tree", required=True)
    p.set_defaults(func=cmd_patch_tree)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        args.func(args)
    except (OSError, ValueError) as exc:
        print(f"prepare.py: error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
