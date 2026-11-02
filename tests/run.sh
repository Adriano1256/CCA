#!/bin/bash
# Roda todos os testes de lógica. Uso: tests/run.sh [pasta temporária]
set -e
O=${1:-/tmp/editor-tests}; mkdir -p "$O"; N=native-ios/EditorIA
CORE="$N/ProjectModel.swift $N/TimelineCore.swift $N/AudioDuckingPlanner.swift $N/DirectorPlanningCore.swift $N/DirectorTimelineMaterializer.swift $N/SceneEvaluator.swift $N/CaptionPresets.swift $N/AgentCore.swift"
swiftc -swift-version 5 $N/DirectorPlanningCore.swift $N/DirectorTimelineMaterializer.swift tests/DirectorPlanningCoreTests.swift -o "$O/d" && "$O/d"
swiftc -swift-version 5 $N/AudioDuckingPlanner.swift tests/AudioDuckingPlannerTests.swift -o "$O/a" && "$O/a"
swiftc -swift-version 5 $CORE tests/TimelineCoreTests.swift -o "$O/t" && "$O/t"
swiftc -swift-version 5 $CORE tests/SceneAndAgentTests.swift -o "$O/s" && "$O/s"
