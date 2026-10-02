// One bounded HTTPS request inside the attached authorized IP-test app.
// Numeric target avoids DNS. Print only public IP/country or error domain/code.
const allowed=new Set(['mobi.secured.whatsmyip','com.monvpn.myip']);
let session,completion;
ObjC.schedule(ObjC.mainQueue,()=>{
 const bundle=ObjC.classes.NSBundle.mainBundle().bundleIdentifier().toString();
 if(!allowed.has(bundle)){console.log('REFUSED_OTHER_APP');return;}
 const request=ObjC.classes.NSMutableURLRequest.requestWithURL_(ObjC.classes.NSURL.URLWithString_('https://1.1.1.1/cdn-cgi/trace'));
 request.setTimeoutInterval_(8);request.setCachePolicy_(1);
 session=ObjC.classes.NSURLSession.sessionWithConfiguration_(ObjC.classes.NSURLSessionConfiguration.ephemeralSessionConfiguration());
 completion=new ObjC.Block({retType:'void',argTypes:['object','object','object'],implementation:(data,response,error)=>{
   if(error){console.log('APP_IP_ERROR '+JSON.stringify({app:bundle,domain:error.domain().toString(),code:error.code()}));}
   else if(data){const body=ObjC.classes.NSString.alloc().initWithData_encoding_(data,4).toString();const ip=/^ip=(.+)$/m.exec(body),country=/^loc=(.+)$/m.exec(body);console.log('APP_EGRESS '+JSON.stringify({app:bundle,ip:ip?ip[1]:null,country:country?country[1]:null}));}
   session.finishTasksAndInvalidate();
 }});
 const task=session.dataTaskWithRequest_completionHandler_(request,completion);task.resume();console.log('APP_IP_REQUEST_STARTED '+bundle);
});
