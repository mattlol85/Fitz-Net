import './css/App.css';
import React from 'react';
import { BrowserRouter, Outlet, Route, Routes } from 'react-router-dom';
import Homepage from './components/Homepage';
import NoPage from './components/NoPage';
import Navbar from './components/Navbar';
import LaurenPanelContent from './components/LaurenPanelContent';
import InfoPanelContent from './components/InfoPanelContent';
import Footer from './components/Footer';


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
      <Footer/>
      <Outlet />
    </BrowserRouter>
  );
}

export default App;