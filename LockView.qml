import QtQuick
import QtQuick.Effects
import Quickshell
import qs.Commons
import qs.Ui

Item {
  id: root

  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false

  readonly property string placeholderText: "Enter Password"

  // ---- macOS-style lock clock
  //
  // A big time with the date above it, set in the upper third of the screen
  // the way macOS lays out its lock screen. Every dimension is a fraction of
  // screen height, so the block keeps its proportions on any monitor, and the
  // password field drops below center to leave the clock its own space.
  //
  // Each value can be overridden from this plugin's entry in shell.json;
  // `settings` is that entry, and the literals here are the defaults.
  property var settings: ({})

  function setting(key, fallback) {
    if (!settings || settings[key] === undefined || settings[key] === null) return fallback
    return settings[key]
  }

  // Weights are named in shell.json rather than given as Qt enum numbers,
  // so a config file stays readable to someone who has never seen Qt.
  function weightFor(name, fallback) {
    var weights = {
      "thin": Font.Thin, "extralight": Font.ExtraLight, "light": Font.Light,
      "normal": Font.Normal, "regular": Font.Normal, "medium": Font.Medium,
      "demibold": Font.DemiBold, "semibold": Font.DemiBold, "bold": Font.Bold,
      "extrabold": Font.ExtraBold, "black": Font.Black
    }
    var resolved = weights[String(name).toLowerCase()]
    return resolved !== undefined ? resolved : fallback
  }

  readonly property string clockFontFamily: setting("fontFamily", "Noto Sans")
  readonly property string clockTimeFormat: setting("timeFormat", "HH:mm")
  readonly property string clockDateFormat: setting("dateFormat", "dddd, d MMMM")
  readonly property real clockOpacity: setting("opacity", 0.55)
  readonly property int clockTimeWeight: weightFor(setting("weight", "bold"), Font.Bold)
  readonly property int clockDateWeight: weightFor(setting("dateWeight", "demibold"), Font.DemiBold)
  readonly property int clockTopFraction: Math.round(height * setting("topScale", 0.09))
  readonly property int clockTimeFontSize: Math.max(48, Math.round(height * setting("timeScale", 0.17)))
  readonly property int clockDateFontSize: Math.max(12, Math.round(clockTimeFontSize * setting("dateScale", 0.16)))
  readonly property color clockColor: Util.alpha(Color.lock.text, clockOpacity)

  // Password field. `fieldOffsetScale` is measured from the vertical center,
  // as a fraction of screen height; `fieldBorder` puts the theme's accent
  // ring back on the resting field for anyone who wants it.
  readonly property int fieldWidth: setting("fieldWidth", 300)
  readonly property int fieldHeight: setting("fieldHeight", 50)
  readonly property real fieldOffsetScale: setting("fieldOffsetScale", 0.27)
  readonly property bool fieldBorder: setting("fieldBorder", false)
  readonly property int outlineThickness: 3
  readonly property int fieldFontSize: Math.round(Style.font.heading * 1.125)
  readonly property int passwordDotFontSize: Math.round(Style.font.heading * 1.33)
  readonly property int passwordDotLetterSpacing: Math.round(Style.font.heading * 0.19)
  // Space to keep clear on each side of the field for the fingerprint icon
  // (icon width plus a gap) so the centered dots never run under it.
  readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
  // Shrink the dots to fit once the password outgrows the field, so every
  // keystroke stays visible — otherwise long passwords clip with no feedback.
  readonly property real passwordDotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth)
    : 1
  readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
  readonly property bool errorState: failureMessage.length > 0
  // No accent ring in the resting state — macOS shows a bare translucent
  // pill. The red outline still comes back on a failed attempt, which is the
  // one moment the border is carrying information.
  readonly property var inputBorderSpec: errorState
    ? Border.surfaceSpec("lock", "border-error", Color.lock.borderError, root.outlineThickness, "border-alpha")
    : (fieldBorder
      ? Border.surfaceSpec("lock", "border-active", Color.lock.borderActive, root.outlineThickness, "border-alpha")
      : Border.none())

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  // Cache-busts the lock background by appending `?v=`. Adding a query
  // string keeps Image's loader happy while forcing it to reload when the
  // user picks a new background mid-session.
  function fileUrl(path) {
    if (!path) return ""
    var encoded = String(path).split("/").map(encodeURIComponent).join("/")
    return "file://" + encoded + "?v=" + backgroundVersion
  }

  function forcePasswordFocus() {
    passwordInput.forceActiveFocus()
  }

  function clearPassword() {
    passwordTextEdited("")
  }

  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: {
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // Measures the masked password at full size; passwordDotScale compares this
  // against the field width to decide how far the dots must shrink to fit.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.passwordDotFontSize
    font.letterSpacing: root.passwordDotLetterSpacing
    text: "●".repeat(passwordInput.text.length)
  }

  Rectangle {
    anchors.fill: parent
    color: Color.background

    Image {
      id: wallpaper
      anchors.fill: parent
      source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: width
      sourceSize.height: height
    }

    MultiEffect {
      anchors.fill: wallpaper
      source: wallpaper
      autoPaddingEnabled: false
      blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
      blur: 1.0
      blurMax: 128
      blurMultiplier: 1.25
      contrast: -0.08
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onClicked: { root.wakeRequested(); root.forcePasswordFocus() }
      onPositionChanged: root.wakeRequested()
    }

    // Minute precision is all the display shows, so the clock only wakes
    // once a minute rather than once a second.
    SystemClock {
      id: lockClock
      precision: SystemClock.Minutes
    }

    Column {
      id: clockBlock
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: root.clockTopFraction
      spacing: Math.round(root.clockDateFontSize * 0.5)

      // The wallpaper behind is arbitrary, so the numerals carry their own
      // soft shadow to stay readable over a light or busy image.
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowBlur: 0.7
        shadowOpacity: 0.4
        shadowColor: Color.background
        shadowVerticalOffset: 2
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDateTime(lockClock.date, root.clockDateFormat)
        color: root.clockColor
        font.family: root.clockFontFamily
        font.pixelSize: root.clockDateFontSize
        font.weight: root.clockDateWeight
        font.letterSpacing: root.clockDateFontSize * 0.02
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: Qt.formatDateTime(lockClock.date, root.clockTimeFormat)
        // Held back from the full foreground so the numerals sit in the
        // wallpaper rather than glaring off it.
        color: root.clockColor
        font.family: root.clockFontFamily
        font.pixelSize: root.clockTimeFontSize
        font.weight: root.clockTimeWeight
        // Large light numerals set loose; a slight negative tracking pulls
        // them back into the tight cluster macOS shows.
        font.letterSpacing: root.clockTimeFontSize * -0.02
      }
    }

    BorderSurface {
      id: inputField
      width: root.fieldWidth
      height: root.fieldHeight
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: Math.round(parent.height * root.fieldOffsetScale)
      color: Color.lock.background
      borderSpec: root.inputBorderSpec
      // A pill rather than the shell's shared corner radius — macOS rounds
      // this field to its full height.
      radius: Math.round(height / 2)
      clip: true

      TextInput {
        id: passwordInput
        anchors.fill: parent
        anchors.topMargin: inputField.borderTop
        // Reserve the fingerprint icon's width on both sides so the centered
        // dots stay symmetric and never slide under the icon as they grow.
        anchors.rightMargin: inputField.borderRight + 18 + root.fingerprintReserve
        anchors.bottomMargin: inputField.borderBottom
        anchors.leftMargin: inputField.borderLeft + 18 + root.fingerprintReserve
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        activeFocusOnPress: true
        clip: true
        enabled: root.inputEnabled && !root.authenticatingPassword
        readOnly: root.authenticatingPassword
        echoMode: TextInput.Password
        passwordCharacter: "\u25CF"
        passwordMaskDelay: 0
        color: Color.lock.text
        selectionColor: Color.lock.selection
        selectedTextColor: Color.lock.text
        font.family: Style.font.family
        font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
        font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
        cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0
        cursorDelegate: Rectangle {
          width: 2
          color: Color.lock.text
          visible: passwordInput.cursorVisible
        }

        onTextChanged: {
          if (!root.syncingPasswordText) root.passwordTextEdited(text)
          if (text.length > 0) {
            root.wakeRequested()
          }
          if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
        }

        onAccepted: {
          var submitted = root.passwordText
          root.passwordTextEdited("")
          if (submitted.length > 0) root.submitPassword(submitted)
        }

        Keys.onPressed: function(event) {
          root.wakeRequested()
          if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
            root.passwordTextEdited("")
            event.accepted = true
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.fill: passwordInput
        text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
        visible: passwordInput.text.length === 0
        color: root.authenticatingPassword ? Color.lock.text : (root.failureMessage.length > 0 ? Color.lock.textError : Color.lock.placeholder)
        font.family: Style.font.family
        font.pixelSize: root.fieldFontSize
        font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
      }

      // Fingerprint hint pinned inside the field's right edge when a sensor is
      // enrolled, so the user knows they can touch to unlock instead of typing.
      // Matches hyprlock, which draws its fingerprint icon in the same spot.
      Text {
        id: fingerprintIcon
        objectName: "fingerprintIndicator"
        anchors.right: parent.right
        anchors.rightMargin: inputField.borderRight + 18
        anchors.verticalCenter: parent.verticalCenter
        visible: root.fingerprintConfigured
        text: "󰈷"
        color: Color.lock.placeholder
        font.family: Style.font.family
        font.pixelSize: Math.round(root.fieldFontSize * 1.1)
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}
