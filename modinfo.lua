name = "Sanity Rate Breakdown"
description = "Displays a breakdown of the current modifiers affecting your sanity over time."
author = "tmatale"
version = "1.0"
api_version = 6
api_version_dst = 10
priority = 0
dst_compatible = true
all_clients_require_mod = false
client_only_mod = true
server_filter_tags = {}

configuration_options =
{
	{
		name = "MAXSOURCES",
		label = "Sources",
		hover = "Show how many sources affecting sanity to display.",
		options =	{
						{description = "2", data = 2},
                        {description = "3", data = 3},
                        {description = "4", data = 4},
                        {description = "5", data = 5},
					},
		default = 5,
    },	
    {
		name = "SHOWTOTAL",
		label = "Total",
		hover = "Show an extra line with the combined total of sanity change.",
		options =	{
						{description = "Show", data = true},
                        {description = "Hide", data = false},
					},
		default = true,
    },	
}