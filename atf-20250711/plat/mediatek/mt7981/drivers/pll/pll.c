/*
 * Copyright (c) 2020, MediaTek Inc. All rights reserved.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include <drivers/delay_timer.h>
#include <lib/mmio.h>
#include <mcucfg.h>
#include <platform_def.h>
#include <common/debug.h>
#include "pll.h"

#define aor(v, a, o)			(((v) & (a)) | (o))
#define VDNR_DCM_TOP_INFRA_CTRL_0	0x1A02003C
#define INFRASYS_BUS_DCM_CTRL		0x10001004

#define ACLKEN_DIV 			0x10400640
#define BUS_PLL_DIVIDER 		0x104007c0

#ifndef MT7981_ARMPLL_FREQ_MHZ
#define MT7981_ARMPLL_FREQ_MHZ		1300U
#endif

/*
 * MT7981 ARMPLL operates with internal VCO in the 2.6GHz - 3.6GHz range.
 * A fixed post-divider of /2 (0x114) is applied to generate the CPU clock.
 * Formula:
 *   VCO_Freq (MHz) = Fcpu (MHz) * 2
 *   PCW = VCO_Freq / 20 = Fcpu / 10
 */
#define ARMPLL_CON1_FROM_MHZ(_mhz)	(((uint32_t)(_mhz) / 10U) << 24)

#if (MT7981_ARMPLL_FREQ_MHZ != 1300U) && \
	(MT7981_ARMPLL_FREQ_MHZ != 1400U) && \
	(MT7981_ARMPLL_FREQ_MHZ != 1500U) && \
	(MT7981_ARMPLL_FREQ_MHZ != 1600U) && \
	(MT7981_ARMPLL_FREQ_MHZ != 1700U) && \
	(MT7981_ARMPLL_FREQ_MHZ != 1800U)
#error "MT7981_ARMPLL_FREQ_MHZ must be one of: 1300, 1400, 1500, 1600, 1700, 1800"
#endif

static unsigned int _mtk_get_cpu_freq(uint32_t valid)
{
	unsigned int temp, clk26cali_0, clk_cfg_9, clk_misc_cfg_1;
	unsigned int read1, read2, bk_mcu;

	bk_mcu = mmio_read_32(0x104007c0);
	mmio_write_32(0x104007c0, 0xe0201);
	clk26cali_0 = mmio_read_32(0x1001B320);
	clk_misc_cfg_1 = mmio_read_32(0x1001B200);
	mmio_write_32(0x1001B200, 0x0);
	clk_cfg_9 = mmio_read_32(0x1001B240);
	mmio_write_32(0x1001B240, 0x00040000);
	mmio_write_32(0x1001B324, (0x27 << 20 | 0x2 << 16 | valid));
	mmio_write_32(0x1001B320, 0x101);
	temp = mmio_read_32(0x1001B320);
	read1 = temp & 0x1;
	while (read1 != 0) {
		temp = mmio_read_32(0x1001B320);
		read1 = temp & 0x1;
	}
	/* Wait for frequency meter to finish */
	mdelay(100);
	read1 = ((temp & 0xffff0000) >> 16);
	read2 = ((temp & 0x00001000) >> 12);
	if ((read1 < (valid - 2)) || (read1 > (valid + 2)) || (read2 == 0))
		return 0;
	mmio_write_32(0x1001B240, clk_cfg_9);
	mmio_write_32(0x1001B200, clk_misc_cfg_1);
	mmio_write_32(0x1001B320, clk26cali_0);
	mmio_write_32(0x104007c0, bk_mcu);

	return read1;
}

unsigned int mtk_get_cpu_freq(void)
{
	unsigned int ret;
	unsigned int valid;

	/* Frequency meter returns approximately Fcpu / 2 (in MHz) */
	valid = MT7981_ARMPLL_FREQ_MHZ / 2U;
	ret = _mtk_get_cpu_freq(valid);
	if (ret > 0U)
		return ret * 2U;

	/* Fallbacks for standard baseline frequencies */
	ret = _mtk_get_cpu_freq(0x28A); /* 1300 / 2 */
	if (ret > 0U)
		return ret * 2U;

	ret = _mtk_get_cpu_freq(0x1F4); /* 1000 / 2 */
	if (ret > 0U)
		return ret * 2U;

	NOTICE("Warning: measured CPU frequency is unexpected\n");
	return 0;
}

void mtk_pll_init(int skip_dcm_setting)
{
	/* Power on PLL */
	mmio_setbits_32(ARMPLL_PWR_CON0, CON0_PWR_ON);
	mmio_setbits_32(NET2PLL_PWR_CON0, CON0_PWR_ON);
	mmio_setbits_32(MMPLL_PWR_CON0, CON0_PWR_ON);
	mmio_setbits_32(SGMIIPLL_PWR_CON0, CON0_PWR_ON);
	mmio_setbits_32(WEDMCUPLL_PWR_CON0, CON0_PWR_ON);
	mmio_setbits_32(NET1PLL1_PWR_CON0, CON0_PWR_ON);
	mmio_setbits_32(APLL2_PWR_CON0, CON0_PWR_ON);
	mmio_setbits_32(MPLL_PWR_CON0, CON0_PWR_ON);

	udelay(1);

	/* Disable PLL isolation */
	mmio_clrbits_32(ARMPLL_PWR_CON0, CON0_ISO_EN);
	mmio_clrbits_32(NET2PLL_PWR_CON0, CON0_ISO_EN);
	mmio_clrbits_32(MMPLL_PWR_CON0, CON0_ISO_EN);
	mmio_clrbits_32(SGMIIPLL_PWR_CON0, CON0_ISO_EN);
	mmio_clrbits_32(WEDMCUPLL_PWR_CON0, CON0_ISO_EN);
	mmio_clrbits_32(NET1PLL1_PWR_CON0, CON0_ISO_EN);
	mmio_clrbits_32(APLL2_PWR_CON0, CON0_ISO_EN);
	mmio_clrbits_32(MPLL_PWR_CON0, CON0_ISO_EN);

	/* Configure ARM PLL frequency and /2 post-divider */
	mmio_write_32(ARMPLL_CON1, ARMPLL_CON1_FROM_MHZ(MT7981_ARMPLL_FREQ_MHZ));
	mmio_setbits_32(ARMPLL_CON0, 0x114);

	mmio_setbits_32(NET2PLL_CON0, 0x114);
	mmio_setbits_32(MMPLL_CON0, 0x124);
	mmio_setbits_32(SGMIIPLL_CON0, 0x134);
	mmio_setbits_32(WEDMCUPLL_CON0, 0x144);
	mmio_setbits_32(NET1PLL1_CON0, 0x104);
	mmio_setbits_32(APLL2_CON0, 0x134);
	mmio_setbits_32(MPLL_CON0, 0x124);

	/* Enable PLL clock output */
	mmio_setbits_32(ARMPLL_CON0, CON0_BASE_EN);
	mmio_setbits_32(NET2PLL_CON0, CON0_BASE_EN);
	mmio_setbits_32(MMPLL_CON0, CON0_BASE_EN);
	mmio_setbits_32(SGMIIPLL_CON0, CON0_BASE_EN);
	mmio_setbits_32(WEDMCUPLL_CON0, CON0_BASE_EN);
	mmio_setbits_32(NET1PLL1_CON0, CON0_BASE_EN);
	mmio_setbits_32(APLL2_CON0, CON0_BASE_EN);	/* 750MHz */
	mmio_setbits_32(MPLL_CON0, CON0_BASE_EN);	/* 650MHz */

	/* Wait for PLL stabilization (min delay is 20us) */
	udelay(20);

	mmio_setbits_32(NET2PLL_CON0, 0x00800000);
	mmio_setbits_32(MMPLL_CON0, 0x00800000);
	mmio_setbits_32(WEDMCUPLL_CON0, 0x00800000);
	mmio_setbits_32(NET1PLL1_CON0, 0x00800000);
	mmio_setbits_32(MPLL_CON0, 0x00800000);

	/* Enable Infra bus divider */
	if (skip_dcm_setting == 0) {
		mmio_setbits_32(VDNR_DCM_TOP_INFRA_CTRL_0, 0x2);
		mmio_write_32(INFRASYS_BUS_DCM_CTRL, 0x5);
	}

	/* Change CPU:CCI clock ratio to 1:2 */
	mmio_clrsetbits_32(ACLKEN_DIV, 0x1f, 0x12);

	/* Switch to ARM CA7 PLL */
	mmio_setbits_32(BUS_PLL_DIVIDER, 0x3000800);
	mmio_setbits_32(BUS_PLL_DIVIDER, (0x1 << 9));

	/* Set default MUX for topckgen */
	mmio_write_32(CLK_CFG_0, 0x00000101);
	mmio_write_32(CLK_CFG_1, 0x01010100);
	mmio_write_32(CLK_CFG_2, 0x01010000);
	mmio_write_32(CLK_CFG_3, 0x01010101);
	mmio_write_32(CLK_CFG_4, 0x01010100);
	mmio_write_32(CLK_CFG_5, 0x01010101);
	mmio_write_32(CLK_CFG_6, 0x01010101);
	mmio_write_32(CLK_CFG_7, 0x01010101);
	mmio_write_32(CLK_CFG_8, 0x01010101);

	mmio_write_32(0x1001B1C0, 0x7FFEFCE3);
	mmio_write_32(0x1001B1C4, 0x3);
}

void mtk_pll_eth_init(void)
{
	mmio_clrsetbits_32(CLK_CFG_4, 0xffffff00, 0x01010100);
	mmio_clrsetbits_32(CLK_CFG_5, 0x00ffffff, 0x00010101);
	mmio_write_32(0x1001B1C0, 0x7e0000);
}
