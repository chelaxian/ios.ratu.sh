// Read-only visible IPv4 labels. Avoid printing other UI or user data.
ObjC.schedule(ObjC.mainQueue,()=>{
 const app=ObjC.classes.UIApplication.sharedApplication();
 const queue=[];const windows=app.windows();for(let i=0;i<windows.count();i++)queue.push(windows.objectAtIndex_(i));
 const seen=new Set();let inspected=0;
 while(queue.length&&++inspected<6000){
  const view=queue.shift();
  if(view.respondsToSelector_(ObjC.selector('text'))){
   const value=view.text();if(value){const matches=value.toString().match(/\b(?:\d{1,3}\.){3}\d{1,3}\b/g)||[];for(const ip of matches)if(ip.split('.').every(n=>Number(n)<=255)&&!seen.has(ip)){seen.add(ip);console.log('VISIBLE_IP '+ip);}}
  }
  const children=view.subviews();for(let i=0;i<children.count();i++)queue.push(children.objectAtIndex_(i));
 }
 console.log('IP_LABEL_SCAN_DONE');
});
