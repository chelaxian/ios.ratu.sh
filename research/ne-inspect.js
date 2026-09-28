for (const name of ['NEPolicySession','NEPolicyResult','NEPolicyCondition','NEVPN','NEVPNApp','NEAppRule','NEProcessInfo','NEConfigurationManager']) {
  const c = ObjC.classes[name];
  console.log(name + ': ' + (c ? c.$ownMethods.join('\n') : 'missing'));
}
