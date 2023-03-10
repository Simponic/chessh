import { useEffect } from "react";
import { Link } from "react-router-dom";

import { useAuthContext } from "../context/auth_context";

export const AuthSuccessful = () => {
  const { player, setPlayer, signedIn, setSignedIn, setSessionOver } =
    useAuthContext();

  useEffect(() => {
    fetch("/api/player/token/me", {
      credentials: "same-origin",
    })
      .then((r) => r.json())
      .then(({ player, expiration }) => {
        setSignedIn(!!player);
        setPlayer(player);
        setSessionOver(expiration);
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (signedIn) {
    return (
      <>
        <h3>Hello there, {player?.username || ""}! </h3>
        <p>You've successfully been authenticated.</p>
        <div>
          <Link to="/home" className="button">
            Get Started
          </Link>
        </div>
      </>
    );
  }
  return (
    <>
      <p>Loading...</p>
    </>
  );
};
