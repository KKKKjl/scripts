import frida
import sys
import time
import uuid
import base64

js = """
rpc.exports = {
    test: function(t, u) {
        var result = "";
        Java.perform(function() {
            console.log("begin");
            
            var currentApplication = Java.use("android.app.ActivityThread").currentApplication();
            var context = currentApplication.getApplicationContext();

            var hook = Java.use("com.pocket.snh48.base.net.utils.EncryptlibUtils");
            result = hook.MD5(context, t, u);
        });
        return result;
    }

};
"""

def on_message(message, data):
    if message['type'] == 'send':
        print("[*] {0}".format(message['payload']))
    else:
        print(message)

def process_script(t, u):
    session = frida.get_usb_device().attach('com.pocket.snh48.activity')
    script = session.create_script(js)
    script.on('message', on_message)
    script.load()
    return script.exports.test(t, u)


def get_pa():
    t = int(time.time()) * 1000
    u = str(uuid.uuid4()).replace('-', '')
    m = process_script(str(t), u)
    pa = base64.b64encode('{},{},{}'.format(t, u, m).encode('utf-8'))
    print(pa)

get_pa()
