// SPDX-License-Identifier: MIT
import QtQuick
import QtTest
import "../../package/contents/ui" as CityUi
import "../../package/contents/ui/code/settings.js" as Settings

Item {
    id: host
    width: 720; height: 440
    // The standalone runner has no Plasma KLocalizedContext.
    function i18nd(domain, text) {
        for (let i=2;i<arguments.length;++i) text=text.replace('%'+(i-1),String(arguments[i]));
        return text;
    }
    Loader { id: formLoader; anchors.fill: parent; active: false; source: "../../package/contents/ui/config.qml" }
    Component {
        id: percentageComponent
        CityUi.SettingControl {
            width: 400
            property real editedValue: -1
            onEdited: function(v) { editedValue=v; value=v; }
        }
    }
    TestCase {
        name: "SettingsNavigationAndWheel"
        when: windowShown
        function findSpin(item) {
            if (typeof item.increase === 'function' && typeof item.textFromValue === 'function') return item;
            if (item.children) for(let i=0;i<item.children.length;++i) { const found=findSpin(item.children[i]); if(found) return found; }
            return null;
        }
        function init() { formLoader.active=true; tryCompare(formLoader,'status',Loader.Ready); wait(100); }
        function cleanup() { formLoader.active=false; wait(20); }
        function test_wheelMovesEachPageFromBody_data() { return [{tag:'look',page:'lookScroll',tab:0},{tag:'animation',page:'animationScroll',tab:1},{tag:'power',page:'powerScroll',tab:2},{tag:'share',page:'shareScroll',tab:3}]; }
        function test_wheelMovesEachPageFromBody(data) {
            const nav=findChild(formLoader.item,'settingsNavigation'); nav.currentIndex=data.tab; wait(60);
            if (data.tab === 0) { findChild(formLoader.item,'previewToggle').checked=true; wait(30); }
            const page=findChild(formLoader.item,data.page);
            // A compact settings window must remain usable without hovering its scrollbar.
            page.contentY=0;
            verify(page.contentHeight>page.height);
            mouseWheel(page,40,70,0,-120); wait(250);
            verify(page.contentY>0,'wheel over page content scrolls '+data.page);
            compare(nav.currentIndex,data.tab);
        }
        function test_wheelOverNumberScrollsWithoutEditing() {
            findChild(formLoader.item,'settingsNavigation').currentIndex=2; wait(60);
            const page=findChild(formLoader.item,'powerScroll'), spin=findSpin(page);
            verify(spin!==null);
            const point=spin.mapToItem(page.contentItem,0,0);
            page.contentY=Math.max(0,point.y-80); wait(20);
            const before=page.contentY, value=formLoader.item.cfg_MaxFps;
            mouseWheel(spin,spin.width/2,spin.height/2,0,-120); wait(250);
            verify(page.contentY>before,'wheel over a numeric input scrolls its page');
            compare(formLoader.item.cfg_MaxFps,value,'scrolling must not change the saved frame cap');
        }
        function test_percentageEditsKeepFractionalRecipeValue() {
            const control=createTemporaryObject(percentageComponent,host,{rule:Settings.schema.BranchProbability,value:0.15,displayMultiplier:100,decimalPlaces:0,unit:'%'});
            wait(60); const spin=findSpin(control); verify(spin!==null);
            compare(spin.textFromValue(spin.value,Qt.locale()),'15');
            spin.forceActiveFocus(); keyClick(Qt.Key_Up); wait(20);
            fuzzyCompare(control.editedValue,0.16,0.000001);
        }
    }
}
