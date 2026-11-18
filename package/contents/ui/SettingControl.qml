// SPDX-License-Identifier: MIT
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kquickcontrols as KQuickControls

ColumnLayout {
    id: root
    required property var rule
    required property var value
    signal edited(var newValue)
    property string explanation: ""
    property var choiceLabels: []
    property real displayMultiplier: 1
    property string unit: ""
    property int decimalPlaces: rule.type === "double" ? 2 : 0
    Layout.fillWidth: true
    Loader {
        Layout.fillWidth: true
        sourceComponent: root.rule.choices ? choiceInput : root.rule.type === "bool" ? boolInput : root.rule.type === "color" ? colorInput : root.rule.type === "int" || root.rule.type === "double" ? numberInput : textInput
    }
    Label { visible: text.length > 0; text: root.explanation; opacity: 0.7; wrapMode: Text.Wrap; Layout.fillWidth: true }
    Component {
        id: choiceInput
        ComboBox {
            wheelEnabled: false
            model: root.choiceLabels.length ? root.choiceLabels : root.rule.choices
            currentIndex: root.rule.choices.indexOf(String(root.value))
            onActivated: root.edited(root.rule.choices[currentIndex])
        }
    }
    Component {
        id: boolInput
        CheckBox { checked: root.value; onToggled: root.edited(checked) }
    }
    Component {
        id: colorInput
        KQuickControls.ColorButton {
            color: root.value
            property bool ready: false
            Component.onCompleted: ready = true
            onColorChanged: if (ready) root.edited(String(color))
        }
    }
    Component {
        id: numberInput
        RowLayout {
            SpinBox {
                id: spin
                wheelEnabled: false
                property int factor: Math.pow(10,root.decimalPlaces)
                from: Math.round(root.rule.min * root.displayMultiplier * factor)
                to: Math.round(root.rule.max * root.displayMultiplier * factor)
                stepSize: root.decimalPlaces > 0 ? 10 : 1
                value: Math.round(Number(root.value) * root.displayMultiplier * factor)
                editable: true
                textFromValue: function(v, locale) { return Number(v / factor).toLocaleString(locale, 'f', root.decimalPlaces); }
                valueFromText: function(text, locale) { return Math.round(Number.fromLocaleString(locale, text) * factor); }
                validator: DoubleValidator { bottom: root.rule.min * root.displayMultiplier; top: root.rule.max * root.displayMultiplier; decimals: root.decimalPlaces }
                onValueModified: root.edited(value / (factor * root.displayMultiplier))
            }
            Label { text: root.unit; visible: text.length > 0 }
            Item { Layout.fillWidth: true }
        }
    }
    Component {
        id: textInput
        TextField {
            text: String(root.value)
            selectByMouse: true
            onEditingFinished: root.edited(text)
        }
    }
}
