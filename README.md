# 역순서

대한민국 도시철도 역 이름을 노선 순서대로 외우는 iOS 26+ SwiftUI 게임입니다.

## 실행

```sh
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project RememberSubway.xcodeproj -scheme RememberSubway \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

프로젝트 생성에는 [XcodeGen](https://github.com/yonaskolb/XcodeGen)을 사용합니다. 앱은 노선 JSON과 진행 기록을 모두 기기에 보관하므로 Game Center 연결 없이도 일반 게임을 플레이할 수 있습니다.

## 노선 데이터

- 앱 데이터: `RememberSubway/Resources/transit_data.json`
- 독립 검증: `swift Tools/validate_transit_data.swift`
- 앱 시작 시에도 동일한 참조 무결성을 검사합니다.

현재 번들 데이터는 앱 구조 검증을 위한 **프리뷰 카탈로그**로, 6개 도시의 대표 1개 노선씩을 포함합니다. App Store 출시 전 국가철도공단 표준데이터와 각 운영기관 공식 노선 자료로 나머지 도시철도·경전철 계통을 추가하고 `contentVersion`을 정식 버전으로 올려야 합니다. 코레일 광역전철은 제품 범위에서 제외합니다.

## Game Center 설정

App Store Connect에서 다음 식별자를 생성해야 실제 제출이 활성화됩니다.

- 7일 반복 리더보드: `kr.co.remembersubway.weekly.v1`
- 업적: `first_segment`, `perfect_segment`, `first_line`, `first_region`, `all_regions`

인증이나 네트워크가 실패하면 일반 게임은 계속되며 주간 최고 점수는 SwiftData에 제출 대기 상태로 저장됩니다.
