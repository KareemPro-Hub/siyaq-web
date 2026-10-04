import {NextResponse} from "next/server";
export function proxy(){
  // The owner explicitly opened the website; repository access stays private.
  const response=NextResponse.next();
  response.headers.set("X-Robots-Tag","noindex, nofollow, noarchive");
  response.headers.set("Cache-Control","no-store");
  return response;
}
