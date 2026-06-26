# Standard Mode is a curated HA-facing surface

Standard Mode is not a goal to expose every Blocky setting in the Home Assistant UI. It is a curated configuration surface for options that are understandable to typical HA home-network operators, solve a common operational problem, and can be rendered safely into Blocky's YAML without making the UI feel like a second copy of the upstream configuration reference.

Custom Config Mode is the escape hatch for specialist Blocky settings. When an issue asks to expose another upstream option, the default answer is not "yes because Blocky supports it"; the option must earn a place in Standard Mode by being broadly useful in the HA context and safe to operate without deep DNS-specific knowledge.

**Considered & rejected:** Treat Standard Mode as full Blocky coverage. Rejected because it makes the HA UI harder to use, increases schema/template/translation/test surface for niche settings, and blurs the already-clear boundary that Custom Config Mode owns complete Blocky YAML.

**Consequence:** Feature triage should classify new Blocky options as either Standard Mode candidates or Custom Config Mode-only settings. Simple, common home-network controls such as upstream IP protocol selection, ECS subnet precision, or blocklist refresh cadence can belong in Standard Mode; specialist or pipeline-oriented settings such as structured log format or special-use domain handling stay in Custom Config Mode unless a concrete HA-centered use case proves otherwise.
