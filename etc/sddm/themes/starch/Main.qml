import QtQuick 2.15
import QtQuick.Layouts 1.15
import SddmComponents 2.0

Rectangle {
    id: root

    readonly property color bg:         "#0f0f0f"
    readonly property color surface:    "#181818"
    readonly property color inputBg:    "#1e1e1e"
    readonly property color borderCol:  "#2a2a2a"
    readonly property color accent:     "#5eead4"
    readonly property color accentHov:  "#2dd4bf"
    readonly property color fg:         "#efefef"
    readonly property color fgMuted:    "#4a4a4a"
    readonly property color fgLabel:    "#7a7a7a"
    readonly property color red:        "#ef4444"
    readonly property color green:      "#22c55e"

    // Scale factor — bump up for 2K/4K displays
    readonly property real s: 1.5

    property int selectedSession: sessionModel.lastIndex

    function sessionIcon(sessionName) {
        var n = sessionName.toLowerCase()
        if (n.indexOf("steam") >= 0) return "images/steam.svg"
        if (n.indexOf("plex")  >= 0) return "images/plex.svg"
        return "images/desktop.svg"
    }

    color: bg

    TextConstants { id: textConstants }

    // Fill all screens
    Repeater {
        model: screenModel
        Rectangle {
            x: geometry.x; y: geometry.y
            width: geometry.width; height: geometry.height
            color: bg
        }
    }

    Connections {
        target: sddm
        function onLoginSucceeded() {
            statusText.color = green
            statusText.text = textConstants.loginSucceeded
            statusAnim.start()
        }
        function onLoginFailed() {
            statusText.color = red
            statusText.text = textConstants.loginFailed
            statusAnim.start()
            passwordInput.text = ""
        }
        function onInformationMessage(message) {
            statusText.color = red
            statusText.text = message
            statusAnim.start()
        }
    }

    function doLogin() {
        sddm.login(usernameInput.text, passwordInput.text, root.selectedSession)
    }

    // Clock — top right
    Column {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin:   s * 28
        anchors.rightMargin: s * 36
        spacing: s * 4

        Text {
            id: clockTime
            anchors.right: parent.right
            color: fg
            font.pixelSize: s * 52
            font.weight: Font.Light
            text: Qt.formatDateTime(new Date(), "hh:mm")

            Timer {
                interval: 1000
                repeat: true
                running: true
                onTriggered: {
                    clockTime.text = Qt.formatDateTime(new Date(), "hh:mm")
                    clockDate.text = Qt.formatDateTime(new Date(), "ddd, MMM d")
                }
            }
        }

        Text {
            id: clockDate
            anchors.right: parent.right
            color: fgMuted
            font.pixelSize: s * 12
            font.letterSpacing: s * 2
            text: Qt.formatDateTime(new Date(), "ddd, MMM d")
        }
    }

    // Center login form
    Item {
        anchors.centerIn: parent
        width: Math.min(parent.width - s * 80, s * 400)
        height: formCol.implicitHeight

    ColumnLayout {
        id: formCol
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        // Hostname
        Text {
            Layout.fillWidth: true
            text: sddm.hostName
            color: fgMuted
            font.pixelSize: s * 11
            font.letterSpacing: s * 4
            horizontalAlignment: Text.AlignHCenter
            Layout.bottomMargin: s * 36
        }

        // ── SESSION SELECTOR ─────────────────────────────────────────────────
        Text {
            text: "SESSION"
            color: fgLabel
            font.pixelSize: s * 9
            font.letterSpacing: s * 2.5
            Layout.bottomMargin: s * 7
        }

        Item {
            id: sessionSelector
            Layout.fillWidth: true
            height: s * 120
            Layout.bottomMargin: s * 32

            activeFocusOnTab: true
            Keys.onLeftPressed:  if (root.selectedSession > 0) root.selectedSession--
            Keys.onRightPressed: if (root.selectedSession < sessionModel.count - 1) root.selectedSession++
            KeyNavigation.tab:     usernameInput
            KeyNavigation.backtab: shutdownBtn

            RowLayout {
                anchors.fill: parent
                spacing: s * 12

                Repeater {
                    model: sessionModel
                    delegate: Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: s * 10
                        color: root.selectedSession === index
                            ? Qt.rgba(0.37, 0.92, 0.83, 0.10)
                            : (cardMouse.containsMouse ? "#1f1f1f" : inputBg)
                        border.color: root.selectedSession === index
                            ? accent
                            : (cardMouse.containsMouse ? "#444444" : borderCol)
                        border.width: root.selectedSession === index ? s * 2 : s * 1

                        Behavior on color        { ColorAnimation { duration: 150 } }
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Column {
                            anchors.centerIn: parent
                            spacing: s * 10

                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width:  s * 44
                                height: s * 44
                                source: root.sessionIcon(name)
                                sourceSize.width:  512
                                sourceSize.height: 512
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: name
                                color: root.selectedSession === index ? accent : fg
                                font.pixelSize: s * 11
                                font.weight: Font.Medium
                                font.letterSpacing: s * 1.5

                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                        }

                        MouseArea {
                            id: cardMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selectedSession = index
                                sessionSelector.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }

        // ── USERNAME ─────────────────────────────────────────────────────────
        Text {
            text: "USERNAME"
            color: fgLabel
            font.pixelSize: s * 9
            font.letterSpacing: s * 2.5
            Layout.bottomMargin: s * 7
        }

        TextBox {
            id: usernameInput
            Layout.fillWidth: true
            height: s * 44

            text: userModel.lastUser

            color:       inputBg
            borderColor: borderCol
            focusColor:  accent
            hoverColor:  "#242424"
            textColor:   fg

            font.pixelSize: s * 15

            KeyNavigation.tab:     passwordInput
            KeyNavigation.backtab: sessionSelector
            Layout.bottomMargin: s * 20
        }

        // ── PASSWORD ─────────────────────────────────────────────────────────
        Text {
            text: "PASSWORD"
            color: fgLabel
            font.pixelSize: s * 9
            font.letterSpacing: s * 2.5
            Layout.bottomMargin: s * 7
        }

        PasswordBox {
            id: passwordInput
            Layout.fillWidth: true
            height: s * 44

            color:       inputBg
            borderColor: borderCol
            focusColor:  accent
            hoverColor:  "#242424"
            textColor:   fg

            tooltipEnabled: true
            tooltipText:    textConstants.capslockWarning
            tooltipFG:      fg
            tooltipBG:      surface

            font.pixelSize: s * 15

            KeyNavigation.tab:     loginBtn
            KeyNavigation.backtab: usernameInput

            Keys.onPressed: {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.doLogin()
                    event.accepted = true
                }
            }

            Layout.bottomMargin: s * 24
        }

        // ── LOGIN ─────────────────────────────────────────────────────────────
        Button {
            id: loginBtn
            Layout.fillWidth: true
            height: s * 46

            text: textConstants.login

            color:        accent
            textColor:    "#0a0a0a"
            borderColor:  accent
            hoverColor:   accentHov
            pressedColor: accentHov
            activeColor:  accentHov

            font.pixelSize: s * 13
            font.weight:    Font.Bold

            KeyNavigation.tab:     rebootBtn
            KeyNavigation.backtab: passwordInput

            onClicked: root.doLogin()

            Keys.onPressed: {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.doLogin()
                    event.accepted = true
                }
            }
        }

        // Status text — hidden until login attempt
        Text {
            id: statusText
            Layout.fillWidth: true
            text: " "
            color: red
            opacity: 0
            font.pixelSize: s * 13
            horizontalAlignment: Text.AlignHCenter
            Layout.topMargin: s * 12

            SequentialAnimation on opacity {
                id: statusAnim
                running: false
                NumberAnimation { to: 1; duration: 150 }
                PauseAnimation   { duration: 2500 }
                NumberAnimation { to: 0; duration: 500 }
            }
        }
    }
    } // Item

    // ── POWER BUTTONS — bottom left, subtle ───────────────────────────────────
    Row {
        anchors.bottom: parent.bottom
        anchors.left:   parent.left
        anchors.bottomMargin: s * 20
        anchors.leftMargin:   s * 28
        spacing: s * 12

        Button {
            id: rebootBtn
            height: s * 34
            width:  s * 110
            text: textConstants.reboot

            color:        surface
            textColor:    fg
            borderColor:  borderCol
            hoverColor:   "#222222"
            pressedColor: "#252525"
            activeColor:  "#222222"

            font.pixelSize: s * 12

            KeyNavigation.tab:     shutdownBtn
            KeyNavigation.backtab: loginBtn

            onClicked: sddm.reboot()
        }

        Button {
            id: shutdownBtn
            height: s * 34
            width:  s * 110
            text: textConstants.shutdown

            color:        surface
            textColor:    fg
            borderColor:  borderCol
            hoverColor:   "#222222"
            pressedColor: "#252525"
            activeColor:  "#222222"

            font.pixelSize: s * 12

            KeyNavigation.tab:     sessionSelector
            KeyNavigation.backtab: rebootBtn

            onClicked: sddm.powerOff()
        }
    }

    Component.onCompleted: {
        if (usernameInput.text === "")
            usernameInput.focus = true
        else
            passwordInput.focus = true
    }
}
