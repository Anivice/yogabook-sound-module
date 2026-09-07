import pathlib
import sys
import textwrap
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from prepare import (  # noqa: E402
    extract_new_file_from_patch,
    patch_cherrytrail_match,
    patch_lenovo_audio,
)


class ExtractPatchTests(unittest.TestCase):
    def test_extracts_new_file_from_mail_patch(self):
        patch = textwrap.dedent("""\
            Subject: [PATCH 1/1] add foo
            diff --git a/a.txt b/a.txt
            new file mode 100644
            --- /dev/null
            +++ b/a.txt
            @@ -0,0 +1,3 @@
            +one
            +two
            +three
            -- 
            2.53.0
        """)
        self.assertEqual(extract_new_file_from_patch(patch, "a.txt"), "one\ntwo\nthree\n")

    def test_missing_target_raises(self):
        with self.assertRaises(ValueError):
            extract_new_file_from_patch("Subject: nothing\n", "missing.c")


class CherryTrailMatchTests(unittest.TestCase):
    def test_inserts_rt5677_before_rt5645(self):
        source = textwrap.dedent("""\
            struct snd_soc_acpi_mach snd_soc_acpi_intel_cherrytrail_machines[] = {
                {
                    .id = "10EC5670",
                    .drv_name = "cht-bsw-rt5672",
                },
                {
                    .comp_ids = &rt5645_comp_ids,
                    .drv_name = "cht-bsw-rt5645",
                },
                {},
            };
        """)
        out = patch_cherrytrail_match(source)
        self.assertIn('.id = "10EC5677"', out)
        self.assertIn('.drv_name = "cht-rt5677"', out)
        self.assertIn('.fw_filename = "intel/fw_sst_22a8.bin"', out)
        self.assertIn('.board = "cht_rt5677"', out)
        self.assertLess(out.index('10EC5677'), out.index('rt5645_comp_ids'))

    def test_is_idempotent(self):
        source = textwrap.dedent("""\
            struct snd_soc_acpi_mach snd_soc_acpi_intel_cherrytrail_machines[] = {
                { .id = "10EC5677", .drv_name = "cht-rt5677" },
                { .comp_ids = &rt5645_comp_ids },
            };
        """)
        self.assertEqual(patch_cherrytrail_match(source), source)


class LenovoAudioPatchTests(unittest.TestCase):
    def setUp(self):
        self.source = textwrap.dedent(r'''\
            static const struct software_node foo = { };
            static const struct x86_i2c_client_info lenovo_yb1_x90_i2c_clients[] __initconst = {
            };
            /* Lenovo Yoga Book X91F/L Windows tablet needs manual instantiation of the fuel-gauge client */
            static const struct x86_i2c_client_info lenovo_yogabook_x91_i2c_clients[] __initconst = {
                {
                    /* BQ27542 fuel-gauge */
                    .board_info = {
                        .type = "bq27542",
                        .addr = 0x55,
                        .dev_name = "bq27542",
                        .swnode = &fg_bq25890_supply_node,
                    },
                    .adapter_path = "\\_SB_.PCI0.I2C1",
                },
            };
            const struct x86_dev_info lenovo_yogabook_x91_info __initconst = {
                .i2c_client_info = lenovo_yogabook_x91_i2c_clients,
                .i2c_client_count = ARRAY_SIZE(lenovo_yogabook_x91_i2c_clients),
            };
            static const struct property_entry later[] = { };
        ''')

    def test_adds_ts3a_and_rt5677_resources(self):
        out = patch_lenovo_audio(self.source)
        self.assertIn('.type = "ts3a227e"', out)
        self.assertIn('.addr = 0x3b', out)
        self.assertIn('.chip = "INT33FF:00"', out)
        self.assertIn('.index = 77', out)
        self.assertIn('PROPERTY_ENTRY_U32("ti,micbias", 7)', out)
        self.assertIn('PROPERTY_ENTRY_GPIO("speaker-enable2-gpios"', out)
        self.assertIn('PROPERTY_ENTRY_GPIO("headphone-enable-gpios"', out)
        self.assertIn('device_add_software_node(codec_dev', out)
        self.assertIn('device_reprobe(codec_dev)', out)
        self.assertIn('.swnode_group = lenovo_yb1_x91_audio_swnodes', out)
        self.assertIn('.init = lenovo_yb1_x91_audio_init', out)
        self.assertIn('.exit = lenovo_yb1_x91_audio_exit', out)
        self.assertIn('.gpiochip_type = X86_GPIOCHIP_CHERRYVIEW', out)

    def test_does_not_depend_on_exact_x91_comment_or_spacing(self):
        source = self.source.replace(
            "/* Lenovo Yoga Book X91F/L Windows tablet needs manual instantiation of the fuel-gauge client */",
            "/* Yoga Book X91: firmware still needs a manually instantiated fuel gauge. */",
        ).replace(
            "};\nconst struct x86_dev_info lenovo_yogabook_x91_info",
            "};\n\nconst struct x86_dev_info lenovo_yogabook_x91_info",
        )
        out = patch_lenovo_audio(source)
        self.assertIn('.type = "ts3a227e"', out)
        self.assertIn('.init = lenovo_yb1_x91_audio_init', out)

    def test_keeps_fuel_gauge(self):
        out = patch_lenovo_audio(self.source)
        self.assertIn('.type = "bq27542"', out)
        self.assertIn('.addr = 0x55', out)

    def test_is_idempotent(self):
        once = patch_lenovo_audio(self.source)
        self.assertEqual(patch_lenovo_audio(once), once)


if __name__ == "__main__":
    unittest.main()
