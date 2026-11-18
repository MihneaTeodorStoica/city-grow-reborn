const {test}=require('node:test');
const assert=require('node:assert/strict');
const vm=require('node:vm');
const fs=require('node:fs');
const context=vm.createContext({});
vm.runInContext(fs.readFileSync('package/contents/ui/code/settings.js','utf8'),context);
const plain=value=>JSON.parse(JSON.stringify(value));
test('complete recipe round-trip preserves user settings',()=>{
 const values=context.defaults(); values.BackgroundColor='#123456'; values.GrowthSpeed=2.75; values.BackgroundImage='file:///tmp/local%20image.png';
 const result=context.parseRecipe(context.exportRecipe(values)); assert.equal(result.ok,true); assert.deepEqual(plain(result.settings),plain(values));
});
test('invalid recipes cannot supply a partially applied settings object',()=>{
 const current=context.defaults(), original=plain(current);
 const base={version:1,settings:plain(current)};
 const cases=[null,[],{}, {...base,version:2},{...base,extra:true},{...base,settings:{...base.settings,Scale:0}},{...base,settings:{...base.settings,Seed:0.5}},{...base,settings:{...base.settings,Paused:'false'}},{...base,settings:{...base.settings,CustomColors:'["#fff","#000"]'}},{...base,settings:{...base.settings,BackgroundColor:'#00112233'}},{...base,settings:{...base.settings,BackgroundImage:'https://example.org/a.png'}},{...base,settings:{...base.settings,BackgroundImage:'file://remote/a.png'}},{...base,settings:{...base.settings,Unknown:1}},{version:1,settings:{Scale:3}}];
 for(const value of cases){const result=context.parseRecipe(JSON.stringify(value)); assert.equal(result.ok,false,JSON.stringify(value)); assert.equal(result.settings,null); assert.deepEqual(plain(current),original);}
 assert.equal(context.parseRecipe('{').ok,false);
 assert.equal(context.parseRecipe(' '.repeat(65537)).ok,false);
 const oversized=JSON.stringify({...base,settings:{...base.settings,BackgroundImage:'file:///tmp/'+ 'é'.repeat(33000)}}); assert.ok(oversized.length<65536); assert.equal(context.parseRecipe(oversized).ok,false);
});
test('named presets do not overwrite background seed or power preferences',()=>{
 const original=context.defaults(); original.Seed=123; original.BackgroundColor='#123456'; original.MaxFps=7;
 const values={...original,...context.preset('Monochrome')}; assert.equal(values.FillCity,false); assert.equal(values.BranchProbability,0.08); assert.equal(values.Seed,123); assert.equal(values.MaxFps,7); assert.equal(values.BackgroundColor,'#123456');
});
