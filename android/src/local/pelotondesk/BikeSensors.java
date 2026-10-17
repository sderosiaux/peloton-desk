package local.pelotondesk;

import android.content.*;
import android.os.*;
import android.util.Log;
import org.json.JSONObject;

/** Read-only interoperability with the Bike V1 callback service. No resistance writes. */
final class BikeSensors implements ServiceConnection {
    private static final String SERVICE = "com.onepeloton.affernetservice.IV1Interface";
    private static final String CALLBACK = "com.onepeloton.affernetservice.IV1Callback";
    private final Context context;
    private IBinder remote;
    private boolean bound, registered;
    private volatile long updated;
    private volatile double rpm, watts;
    private volatile int resistance;
    private volatile String detail = "Connexion aux capteurs…";
    BikeSensors(Context context) { this.context = context; }

    void start() {
        try {
            Intent intent = new Intent(SERVICE).setComponent(new ComponentName("com.onepeloton.affernetservice", "com.onepeloton.affernetservice.AffernetService"));
            bound = context.bindService(intent, this, Context.BIND_AUTO_CREATE);
            if (!bound) detail = "Le service de capteurs n’est pas accessible.";
        } catch (Exception error) { detail = "Accès aux capteurs refusé par le firmware."; Log.w("PelotonDesk",detail,error); }
    }
    @Override public void onServiceConnected(ComponentName name, IBinder service) {
        remote = service;
        try { transact(1); registered=true; detail="En attente des données du vélo."; Log.i("PelotonDesk","Sensor callback registered"); }
        catch (Exception error) { detail="Le firmware refuse la lecture des capteurs."; Log.w("PelotonDesk",detail,error); }
    }
    @Override public void onServiceDisconnected(ComponentName name) { remote=null; registered=false; updated=0; detail="Capteurs déconnectés."; }
    private void transact(int code) throws RemoteException {
        Parcel data=Parcel.obtain(), reply=Parcel.obtain();
        try { data.writeInterfaceToken(SERVICE); data.writeStrongBinder(callback); data.writeString("Peloton Desk");
            if (!remote.transact(code,data,reply,0)) throw new RemoteException("Sensor protocol unavailable");
            reply.readException();
        } finally { data.recycle(); reply.recycle(); }
    }
    private final Binder callback = new Binder() {
        @Override protected boolean onTransact(int code, Parcel data, Parcel reply, int flags) throws RemoteException {
            if (code==INTERFACE_TRANSACTION) { if(reply!=null)reply.writeString(CALLBACK); return true; }
            if (code!=1) return super.onTransact(code,data,reply,flags);
            try {
                data.enforceInterface(CALLBACK);
                if (data.readInt()!=0) {
                    long nextRpm=data.readLong(), power=data.readLong();
                    data.readLong(); data.readLong();
                    int nextResistance=data.readInt();
                    if(nextRpm>=0 && nextRpm<250 && power>=0 && power<300000 && nextResistance>=0 && nextResistance<=100) {
                        if(updated==0)Log.i("PelotonDesk","First sensor sample received: cadence="+nextRpm+", resistance="+nextResistance);
                        rpm=nextRpm; watts=power/100.0; resistance=nextResistance; updated=SystemClock.elapsedRealtime(); detail="Capteurs connectés.";
                    }
                }
                if(reply!=null)reply.writeNoException();
                return true;
            } catch (RuntimeException error) { detail="Format des données capteurs non reconnu."; return false; }
        }
    };
    synchronized String json() {
        JSONObject value=new JSONObject();
        try {
            boolean live=updated>0 && SystemClock.elapsedRealtime()-updated<5000;
            value.put("available",live); value.put("detail",live?detail:(updated>0?"Données capteurs trop anciennes.":detail));
            if(live) { value.put("cadence",rpm); value.put("resistance",resistance); value.put("power",watts); value.put("speed",speedKmh(watts)); }
        } catch(Exception ignored) { }
        return value.toString();
    }
    // Peloton V1's published power-to-speed approximation; mph converted to km/h.
    // Formula source: https://ihaque.org/posts/2020/12/25/pelomon-part-ib-computing-speed/
    private static double speedKmh(double power) {
        if(power<0.1)return 0;
        double x=Math.sqrt(power);
        double mph=power<26 ? ((-0.079*x+0.759)*x-0.172)*x+0.057 : ((0.001*x-0.064)*x+2.325)*x-1.635;
        return Math.max(0,mph*1.609344);
    }
    void stop() {
        if(registered && remote!=null)try{transact(2);}catch(Exception ignored){}
        if(bound)context.unbindService(this);
        registered=false; bound=false; remote=null;
    }
}
