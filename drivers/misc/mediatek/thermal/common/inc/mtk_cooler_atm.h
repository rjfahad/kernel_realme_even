/*
 * Copyright (C) 2017 MediaTek Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See http://www.gnu.org/licenses/gpl-2.0.html for more details.
 */

/* include both cpu & gpu power */
extern int clatm_get_curr_opp_power(void);

/*
 * Minimum TJ target (milli-Celsius) accepted from the vendor thermal
 * daemon (thermalloadalgod / cATM+). Stock realme UI pushes TTJ as low
 * as 60000, which clamps the big CPU cluster below 1GHz and boxes the
 * GPU near its minimum OPP during gaming. Requests below this floor
 * are raised to it. Set to 0 to restore stock behaviour.
 */
#define ATM_TTJ_FLOOR 70000

