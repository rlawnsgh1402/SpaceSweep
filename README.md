# SpaceSweep

<p align="center"><img src="Resources/icon_1024.png" width="160" alt="SpaceSweep icon"></p>

**English** · A macOS app that shows what's filling up "System Data" and cleans it up safely: an overview of System Data by category, one-click cleanup of caches and build files that are recreated automatically, a picker for developer files (Xcode, simulators, Docker/Colima, AI models, Android), and an app uninstaller that also removes the app's leftover data. Everything goes to the Trash by default, and a final path check refuses to touch your home folder, documents, iCloud, Keychains or system folders. The UI follows your Mac's language (English or Korean). Build with `./build.sh` (macOS 14+, Apple Silicon).

---

**한국어** · macOS의 "시스템 데이터"가 무엇으로 차 있는지 보여주고, 안전하게 정리하는 앱입니다. 화면 언어는 Mac의 기본 언어(한국어/영어)를 따릅니다.

## 기능

- **개요** — 디스크 사용량과 시스템 데이터 구성(시뮬레이터, 앱 데이터, 캐시, 숨김 폴더, macOS 관리 항목 등)을 항목별로 보여주고, 각 항목에서 할 수 있는 일을 안내합니다. 지워도 다시 생기는 항목만 한 번에 정리하는 **추천 정리**를 제공합니다.
- **공간 정리** — 앱 캐시, Xcode DerivedData·DeviceSupport, 오래된 시뮬레이터 런타임, Docker(Colima) 이미지·VM, LM Studio·Ollama 모델, Android 에뮬레이터 등을 항목별로 골라 정리합니다.
- **앱 제거** — 앱과 함께 `~/Library`에 남은 설정·캐시·컨테이너를 찾아 같이 지웁니다. 앱은 남기고 데이터만 지우는(초기화) 것도 가능합니다.

## 안전장치

- 기본적으로 모든 파일은 **휴지통으로 이동**합니다(휴지통을 비우기 전까지 복구 가능).
- 모든 삭제는 마지막에 경로 검사를 거칩니다. 홈 폴더, `~/Library` 최상위 폴더, 문서·데스크탑·다운로드·사진·iCloud·키체인·`.ssh`, 시스템 폴더는 어떤 경우에도 지우지 않습니다.
- 앱 데이터는 번들 ID와 정확히 일치하는 것만 자동 선택하고, 이름만 일치하는 항목은 직접 확인하도록 선택 해제 상태로 둡니다.
- 디스크 이미지 마운트 지점은 크기 계산과 삭제 대상에서 제외합니다.
- macOS가 관리하는 항목(시스템 에셋, 로그, 스왑 등)은 건드리지 않고 안내만 합니다.

## 빌드

Xcode(또는 Command Line Tools)가 설치된 Apple Silicon Mac에서:

```bash
./build.sh
```

`build/SpaceSweep.app`과 `build/SpaceSweep.dmg`가 만들어집니다. 앱 아이콘은 `Tools/make_icon.swift`로 생성합니다.

> 개발자 서명이 없는 빌드라 다른 Mac에서 처음 열 때는 우클릭 → **열기**를 눌러야 합니다.
> 다른 앱의 보호된 컨테이너까지 지우려면 시스템 설정 → 개인정보 보호 및 보안 → **전체 디스크 접근 권한**에서 SpaceSweep을 허용하세요.

## 요구 사항

- macOS 14 이상, Apple Silicon

## 구조

| 파일 | 내용 |
|---|---|
| `Sources/SpaceSweep.swift` | 검사(Scanner), 삭제 안전장치(SafeDelete), 정리 로직 |
| `Sources/SystemData.swift` | 시스템 데이터 분석, 개요 화면 |
| `Sources/Uninstaller.swift` | 앱 목록, 남은 데이터 찾기, 앱 제거 로직 |
| `Sources/UI.swift` | 공간 정리·앱 제거 화면, 사이드바 |
| `Tools/make_icon.swift` | 앱 아이콘 그리기 |
| `build.sh` | 빌드·서명·DMG 생성 |
