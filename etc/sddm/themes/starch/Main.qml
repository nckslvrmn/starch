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

    property int selectedSession: sessionModel.lastIndex

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
        anchors.topMargin: 28
        anchors.rightMargin: 36
        spacing: 4

        Text {
            id: clockTime
            anchors.right: parent.right
            color: fg
            font.pixelSize: 52
            font.weight: Font.Light
            text: Qt.formatDateTime(new Date(), "hh:mm")

            Timer {
                interval: 10000
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
            font.pixelSize: 12
            font.letterSpacing: 2
            text: Qt.formatDateTime(new Date(), "ddd, MMM d")
        }
    }

    // Center login form
    Item {
        anchors.centerIn: parent
        width: Math.min(parent.width - 80, 400)
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
            font.pixelSize: 11
            font.letterSpacing: 4
            horizontalAlignment: Text.AlignHCenter
            Layout.bottomMargin: 36
        }

        // ── SESSION SELECTOR ─────────────────────────────────────────────────
        Text {
            text: "SESSION"
            color: fgLabel
            font.pixelSize: 9
            font.letterSpacing: 2.5
            Layout.bottomMargin: 7
        }

        Item {
            id: sessionSelector
            Layout.fillWidth: true
            height: 44
            Layout.bottomMargin: 32

            activeFocusOnTab: true
            Keys.onLeftPressed:  if (root.selectedSession > 0) root.selectedSession--
            Keys.onRightPressed: if (root.selectedSession < sessionModel.count - 1) root.selectedSession++
            KeyNavigation.tab:     usernameInput
            KeyNavigation.backtab: shutdownBtn

            Rectangle {
                anchors.fill: parent
                color: inputBg
                radius: 8
                border.color: parent.activeFocus ? accent : borderCol
                border.width: 1
            }

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                    model: sessionModel
                    delegate: Rectangle {
                        width: pillText.implicitWidth + 20
                        height: 28
                        radius: 14
                        color: root.selectedSession === index ? accent : "transparent"
                        border.color: root.selectedSession === index ? accent : "#3a3a3a"
                        border.width: 1

                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            id: pillText
                            anchors.centerIn: parent
                            text: name
                            color: root.selectedSession === index ? "#0a0a0a" : fg
                            font.pixelSize: 12
                            font.weight: Font.Medium

                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        MouseArea {
                            anchors.fill: parent
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
            font.pixelSize: 9
            font.letterSpacing: 2.5
            Layout.bottomMargin: 7
        }

        TextBox {
            id: usernameInput
            Layout.fillWidth: true
            height: 44

            color:       inputBg
            borderColor: borderCol
            focusColor:  accent
            hoverColor:  "#242424"
            textColor:   fg

            font.pixelSize: 15

            KeyNavigation.tab:     passwordInput
            KeyNavigation.backtab: sessionSelector
            Layout.bottomMargin: 20
        }

        // ── PASSWORD ─────────────────────────────────────────────────────────
        Text {
            text: "PASSWORD"
            color: fgLabel
            font.pixelSize: 9
            font.letterSpacing: 2.5
            Layout.bottomMargin: 7
        }

        PasswordBox {
            id: passwordInput
            Layout.fillWidth: true
            height: 44

            color:       inputBg
            borderColor: borderCol
            focusColor:  accent
            hoverColor:  "#242424"
            textColor:   fg

            tooltipEnabled: true
            tooltipText:    textConstants.capslockWarning
            tooltipFG:      fg
            tooltipBG:      surface

            font.pixelSize: 15

            KeyNavigation.tab:     loginBtn
            KeyNavigation.backtab: usernameInput

            Keys.onPressed: {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.doLogin()
                    event.accepted = true
                }
            }

            Layout.bottomMargin: 24
        }

        // ── LOGIN ─────────────────────────────────────────────────────────────
        Button {
            id: loginBtn
            Layout.fillWidth: true
            height: 46

            text: textConstants.login

            color:        accent
            textColor:    "#0a0a0a"
            borderColor:  accent
            pressedColor: accentHov
            activeColor:  accentHov

            font.pixelSize: 13
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
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            Layout.topMargin: 12

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
        anchors.bottomMargin: 20
        anchors.leftMargin:   28
        spacing: 12

        Button {
            id: rebootBtn
            height: 34
            width:  110
            text: textConstants.reboot

            color:        surface
            textColor:    fgMuted
            borderColor:  borderCol
            pressedColor: "#252525"
            activeColor:  "#222222"

            font.pixelSize: 12

            KeyNavigation.tab:     shutdownBtn
            KeyNavigation.backtab: loginBtn

            onClicked: sddm.reboot()
        }

        Button {
            id: shutdownBtn
            height: 34
            width:  110
            text: textConstants.shutdown

            color:        surface
            textColor:    fgMuted
            borderColor:  borderCol
            pressedColor: "#252525"
            activeColor:  "#222222"

            font.pixelSize: 12

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
