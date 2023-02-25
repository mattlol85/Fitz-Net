import './App.css';
import React from 'react';
import { BrowserRouter, Outlet, Route, Routes } from 'react-router-dom';
import Homepage from './Homepage';
import NoPage from './NoPage';
import Navbar from './Navbar';
import LaurenPanelContent from './LaurenPanelContent';
import InfoPanelContent from './InfoPanelContent';


function App() {
  return (
    <BrowserRouter>
      <Navbar />
      <Routes>
        <Route path="/home" element={<Homepage />}></Route>
        <Route index element={<Homepage />} />
        <Route path="/laurenpanel" element={<LaurenPanelContent />}> </Route>
        <Route path="/info" element={<InfoPanelContent />} />
        <Route path="*" element={<NoPage />} />
      </Routes>
      <Outlet />
    </BrowserRouter>
  );
}

export default App;